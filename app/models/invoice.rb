class Invoice < ApplicationRecord
  belongs_to :organization
  belongs_to :contact,            optional: true
  belongs_to :receivable_account, class_name: "Plutus::Asset"
  belongs_to :revenue_account,    class_name: "Plutus::Revenue"
  belongs_to :tax_rate,           optional: true
  has_many   :entries, class_name: "Plutus::Entry", as: :commercial_document
  has_many_attached :attachments
  include HasBalanceDue

  before_validation :sync_client_name_from_contact
  before_validation :compute_totals
  validates :client_name, :amount, :due_date, presence: true
  validates :amount, numericality: { greater_than: 0 }
  validate  :tax_rate_has_liability_account, if: -> { tax_rate.present? }

  after_create :post_to_ledger

  def customer_display = contact&.name.presence || client_name

  def status
    return "paid"    if paid?
    return "partial" if paid_amount.positive?
    Date.current > due_date ? "overdue" : "open"
  end

  private

  def sync_client_name_from_contact
    self.client_name = contact.name if contact && client_name.blank?
  end

  # `amount` in the form is the SUBTOTAL. We compute tax on it and store the
  # inclusive total back into `amount` so payments etc. see the full figure.
  def compute_totals
    return if amount.blank?
    if tax_rate && !tax_rate.zero?
      self.subtotal   = amount if subtotal.blank? || subtotal == amount
      self.tax_amount = (subtotal * tax_rate.rate).round(2)
      self.amount     = subtotal + tax_amount
    else
      self.subtotal   = amount
      self.tax_amount = 0
    end
  end

  def tax_rate_has_liability_account
    errors.add(:tax_rate, "needs a liability account for sales tax") if tax_rate.liability_account.blank?
  end

  def post_to_ledger
    credits = [{ account: revenue_account, amount: subtotal }]
    credits << { account: tax_rate.liability_account, amount: tax_amount } if tax_amount.positive?

    Ledger.post(
      description: "Invoice ##{id} — #{client_name}",
      date: created_at&.to_date || Date.current,
      commercial_document: self,
      debits:  [{ account: receivable_account, amount: amount }],
      credits: credits
    )
  end
end

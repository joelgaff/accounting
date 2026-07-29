class Expense < ApplicationRecord
  belongs_to :organization
  belongs_to :contact,           optional: true
  belongs_to :expense_account,   class_name: "Plutus::Expense"
  belongs_to :paid_from_account, class_name: "Plutus::Account"
  belongs_to :tax_rate,          optional: true
  has_many   :entries, class_name: "Plutus::Entry", as: :commercial_document
  has_many_attached :receipts
  include HasBalanceDue

  before_validation :sync_vendor_from_contact
  before_validation :compute_totals
  validates :vendor, :amount, :incurred_on, presence: true
  validates :amount, numericality: { greater_than: 0 }
  validate  :paid_from_must_be_asset_or_liability

  after_create :post_to_ledger

  def vendor_display = contact&.name.presence || vendor

  def status
    return "paid"    if paid?
    return "partial" if paid_amount.positive?
    "open"
  end

  private

  def sync_vendor_from_contact
    self.vendor = contact.name if contact && vendor.blank?
  end

  def paid_from_must_be_asset_or_liability
    return if paid_from_account.is_a?(Plutus::Asset) || paid_from_account.is_a?(Plutus::Liability)
    errors.add(:paid_from_account, "must be an asset or liability account")
  end

  # Amount in the form is the SUBTOTAL. Tax is added on top.
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

  def post_to_ledger
    debits = [{ account: expense_account, amount: subtotal }]
    if tax_amount.positive?
      # If the tax rate has a recoverable asset (input VAT), debit that.
      # Otherwise the tax hits the expense itself (non-recoverable).
      if tax_rate.asset_account
        debits << { account: tax_rate.asset_account, amount: tax_amount }
      else
        debits.first[:amount] = subtotal + tax_amount
      end
    end
    Ledger.post(
      description: "Expense: #{vendor} — #{expense_account.name}",
      date: incurred_on,
      commercial_document: self,
      debits:  debits,
      credits: [{ account: paid_from_account, amount: amount }]
    )
  end
end

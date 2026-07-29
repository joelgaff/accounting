class Invoice < ApplicationRecord
  belongs_to :organization
  belongs_to :contact,            optional: true
  belongs_to :receivable_account, class_name: "Plutus::Asset"
  belongs_to :revenue_account,    class_name: "Plutus::Revenue", optional: true  # deprecated; carried by line items now
  belongs_to :tax_rate,           optional: true                                  # deprecated; carried by line items now
  has_many   :entries, class_name: "Plutus::Entry", as: :commercial_document
  has_many_attached :attachments
  include HasBalanceDue
  include HasLineItems

  before_validation :sync_client_name_from_contact
  before_validation :default_line_from_flat_amount
  before_validation :sync_amount_from_lines
  validates :client_name, :due_date, presence: true
  validates :amount, numericality: { greater_than: 0 }
  validate  :must_have_line_items

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

  # Legacy convenience: if the caller passed a top-level `amount` (subtotal)
  # and no line items, generate a single line from it. Preserves the pre-Slice-H
  # API used across existing tests and imports.
  def default_line_from_flat_amount
    return if line_items.any? || amount.blank? || revenue_account.blank?
    line_items.build(
      description: "Services rendered",
      quantity:    1,
      unit_amount: attributes["subtotal"].presence || amount,
      account:     revenue_account,
      tax_rate:    tax_rate
    )
  end

  def sync_amount_from_lines
    return if line_items.empty?
    self.subtotal   = subtotal
    self.tax_amount = tax_amount
    self.amount     = total
  end

  def must_have_line_items
    errors.add(:base, "must have at least one line item") if line_items.empty?
  end

  def post_to_ledger
    legs = line_ledger_legs
    credits  = legs[:accounts].map { |acct, amt| { account: acct, amount: amt } }
    credits += legs[:taxes].map    { |tax, amt| { account: tax.liability_account, amount: amt } }

    Ledger.post(
      description: "Invoice ##{id} — #{client_name}",
      date: created_at&.to_date || Date.current,
      commercial_document: self,
      debits:  [{ account: receivable_account, amount: amount }],
      credits: credits
    )
  end
end

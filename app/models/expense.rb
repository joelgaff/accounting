class Expense < ApplicationRecord
  belongs_to :organization
  belongs_to :contact,           optional: true
  belongs_to :expense_account,   class_name: "Plutus::Expense", optional: true   # deprecated; carried by line items now
  belongs_to :paid_from_account, class_name: "Plutus::Account"
  belongs_to :tax_rate,          optional: true                                    # deprecated; carried by line items now
  has_many   :entries, class_name: "Plutus::Entry", as: :commercial_document
  has_many_attached :receipts
  include HasBalanceDue
  include HasLineItems

  before_validation :sync_vendor_from_contact
  before_validation :default_line_from_flat_amount
  before_validation :sync_amount_from_lines
  validates :vendor, :incurred_on, presence: true
  validates :amount, numericality: { greater_than: 0 }
  validate  :paid_from_must_be_asset_or_liability
  validate  :must_have_line_items

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

  def default_line_from_flat_amount
    return if line_items.any? || amount.blank? || expense_account.blank?
    line_items.build(
      description: "Expense",
      quantity:    1,
      unit_amount: attributes["subtotal"].presence || amount,
      account:     expense_account,
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

    debits = legs[:accounts].map { |acct, amt| { account: acct, amount: amt } }
    legs[:taxes].each do |tax, amt|
      if tax.asset_account
        debits << { account: tax.asset_account, amount: amt }
      else
        # Non-recoverable tax rolls back onto every expense line
        # proportionally. Simplest: fold onto the first line's account.
        # (Xero and QBO both allow this in "gross" mode.)
        first_acct = debits.first[:account]
        debits.first[:amount] += amt
      end
    end

    Ledger.post(
      description: "Expense: #{vendor} — #{line_items.first.account.name}",
      date: incurred_on,
      commercial_document: self,
      debits:  debits,
      credits: [{ account: paid_from_account, amount: amount }]
    )
  end
end

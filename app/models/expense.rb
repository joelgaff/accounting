class Expense < ApplicationRecord
  belongs_to :organization
  belongs_to :contact,           optional: true
  belongs_to :expense_account,   class_name: "Plutus::Expense"
  belongs_to :paid_from_account, class_name: "Plutus::Account"
  has_many   :entries, class_name: "Plutus::Entry", as: :commercial_document
  has_many   :payments, as: :payable, dependent: :restrict_with_error

  before_validation :sync_vendor_from_contact
  validates :vendor, :amount, :incurred_on, presence: true
  validates :amount, numericality: { greater_than: 0 }
  validate  :paid_from_must_be_asset_or_liability

  after_create :post_to_ledger

  def vendor_display = contact&.name.presence || vendor

  def paid_amount = payments.sum(:amount)
  def balance_due = amount - paid_amount
  def paid?       = balance_due <= 0
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

  def post_to_ledger
    Ledger.post(
      description: "Expense: #{vendor} — #{expense_account.name}",
      date: incurred_on,
      commercial_document: self,
      debits:  [{ account: expense_account,   amount: amount }],
      credits: [{ account: paid_from_account, amount: amount }]
    )
  end
end

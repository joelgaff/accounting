class Payment < ApplicationRecord
  belongs_to :organization
  belongs_to :payable, polymorphic: true
  belongs_to :bank_account, class_name: "Plutus::Asset"
  has_many   :entries, class_name: "Plutus::Entry", as: :commercial_document

  validates :amount, numericality: { greater_than: 0 }
  validates :paid_on, presence: true
  validate  :amount_within_balance_due, on: :create
  validate  :payable_belongs_to_org

  after_create :post_to_ledger

  def direction
    payable.is_a?(Invoice) ? :received : :made
  end

  private

  def payable_belongs_to_org
    return if payable.nil? || payable.organization_id == organization_id
    errors.add(:payable, "must belong to this organization")
  end

  def amount_within_balance_due
    return if payable.nil? || amount.nil?
    already = payable.payments.sum(:amount)
    if already + amount > payable.amount
      errors.add(:amount, "exceeds balance due ($#{'%.2f' % (payable.amount - already)})")
    end
  end

  def post_to_ledger
    debit, credit = ledger_legs
    Ledger.post(
      description: description,
      commercial_document: self,
      debits:  [{ account: debit,  amount: amount }],
      credits: [{ account: credit, amount: amount }]
    )
  end

  # For payments received: money enters the bank, AR falls.
  # For payments made:     money leaves the bank, AP or the paid_from account falls.
  def ledger_legs
    case payable
    when Invoice
      [bank_account, payable.receivable_account]
    when Expense
      [payable.paid_from_account, bank_account]
    end
  end

  def description
    case payable
    when Invoice then "Payment received: Invoice ##{payable.id} — #{payable.customer_display}"
    when Expense then "Payment made: Expense ##{payable.id} — #{payable.vendor_display}"
    end
  end
end

# A settlement against a document that can take one (invoice or bill). The
# type says which accounts move; the payment only knows the bank and the amount.
class Payment < ApplicationRecord
  belongs_to :organization
  belongs_to :document
  belongs_to :bank_account
  has_many   :entries, class_name: "Plutus::Entry", as: :commercial_document

  validates :amount, numericality: { greater_than: 0 }
  validates :paid_on, presence: true
  validate  :document_takes_payments
  validate  :document_belongs_to_org
  validate  :amount_within_balance_due, on: :create

  after_create :post_to_ledger

  def direction = document.documentable.settlement_direction
  def label     = "Payment ##{id}"

  private

  def document_takes_payments
    return if document.nil? || document.settleable?
    errors.add(:document, "cannot take payments")
  end

  def document_belongs_to_org
    return if document.nil? || document.organization_id == organization_id
    errors.add(:document, "must belong to this organization")
  end

  def amount_within_balance_due
    return if document.nil? || amount.nil?
    already = document.payments.sum(:amount)
    if already + amount > document.total
      errors.add(:amount, "exceeds balance due ($#{'%.2f' % (document.total - already)})")
    end
  end

  def post_to_ledger
    debit, credit = document.documentable.settlement_legs(bank_account)
    Ledger.post(
      description: "Payment #{direction == :received ? 'received' : 'made'}: #{document.label} — #{document.counterparty}",
      date: paid_on,
      commercial_document: self,
      debits:  [ { account: debit,  amount: amount } ],
      credits: [ { account: credit, amount: amount } ]
    )
  end
end

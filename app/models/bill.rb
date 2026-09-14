# Something received that still has to be paid: accrued to a payable
# (liability) account and settled later by a payment.
class Bill < ApplicationRecord
  include PurchaseDocument

  belongs_to :payable_account, class_name: "Plutus::Liability"

  def settleable? = true

  def status
    return "paid"    if document.paid?
    return "partial" if document.paid_amount.positive?
    "open"
  end

  def ledger_legs(document)
    { debits: purchase_debits(document), credits: [ { account: payable_account, amount: document.total } ] }
  end

  def ledger_description(document) = "Bill: #{document.counterparty} — #{first_category_name(document)}"

  # Money out against the accrual: the liability comes down, the bank goes down.
  def settlement_legs(bank_account) = [ payable_account, bank_account.account ]
  def settlement_direction          = :made
end

# Money out, paid straight from a bank account or card (Xero's Spend Money).
# Already settled the moment it exists, so it never takes payments.
class Expense < ApplicationRecord
  include PurchaseDocument

  belongs_to :bank_account

  def status = "paid"

  def ledger_legs(document)
    { debits: purchase_debits(document), credits: [ { account: bank_account.account, amount: document.total } ] }
  end

  def ledger_description(document) = "Expense: #{document.counterparty} — #{first_category_name(document)}"
end

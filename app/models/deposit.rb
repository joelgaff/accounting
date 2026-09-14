# Money in that is not an invoice payment (Xero's Receive Money): a sponsor
# cheque, a refund, interest. Lines go to revenue or any other account.
class Deposit < ApplicationRecord
  include Documentable

  belongs_to :bank_account

  def status = "received"

  # DR the bank for the gross; CR each line's account and the tax it carries
  # (sales tax owed, or a purchase-tax asset when input tax is refunded).
  def ledger_legs(document)
    legs     = document.line_ledger_legs
    credits  = legs[:accounts].map { |acct, amt| { account: acct, amount: amt } }
    credits += legs[:taxes].map    { |tax, amt| { account: tax.liability_account || tax.asset_account, amount: amt } }
    { debits: [ { account: bank_account.account, amount: document.total } ], credits: credits }
  end

  def ledger_description(document) = "Deposit: #{document.display_name}"
end

# Money moved between two of our own bank accounts or cards. No line items;
# the amount lives on the document. Each side's statement line links to the
# same document once it arrives.
class Transfer < ApplicationRecord
  include Documentable

  belongs_to :from_bank_account, class_name: "BankAccount"
  belongs_to :to_bank_account,   class_name: "BankAccount"

  validate :distinct_accounts

  def line_items? = false
  def status      = "posted"

  def totals_for(document) = [ document.total, BigDecimal("0") ]

  def ledger_legs(document)
    {
      debits:  [ { account: to_bank_account.account,   amount: document.total } ],
      credits: [ { account: from_bank_account.account, amount: document.total } ]
    }
  end

  def ledger_description(_document) = "Transfer: #{from_bank_account.name} → #{to_bank_account.name}"
  def party_name = "#{from_bank_account.name} → #{to_bank_account.name}"

  # The statement line each side expects: money out of `from`, money into `to`.
  def expected_amount_for(bank_account)
    return -document.total if bank_account == from_bank_account
    document.total if bank_account == to_bank_account
  end

  def side_matched?(bank_account)  = document.bank_transactions.any? { |t| t.bank_account_id == bank_account.id }
  def awaiting_side?(bank_account) = expected_amount_for(bank_account).present? && !side_matched?(bank_account)

  private

  def distinct_accounts
    errors.add(:to_bank_account, "must differ from the source account") if from_bank_account_id.present? && from_bank_account_id == to_bank_account_id
  end
end

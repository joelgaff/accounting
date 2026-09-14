class Invoice < ApplicationRecord
  include Documentable

  belongs_to :receivable_account, class_name: "Plutus::Asset"

  before_validation :sync_client_name_from_contact
  validates :client_name, :due_date, presence: true

  def party_name  = client_name
  def settleable? = true

  def status
    return "paid"    if document.paid?
    return "partial" if document.paid_amount.positive?
    Date.current > due_date ? "overdue" : "open"
  end

  def tax_rate_display
    names = document.line_items.filter_map { |li| li.tax_rate&.name }.uniq
    names.presence&.to_sentence || "Tax"
  end

  # DR accounts receivable for the gross; CR each revenue account and each
  # tax rate's liability account.
  def ledger_legs(document)
    legs     = document.line_ledger_legs
    credits  = legs[:accounts].map { |acct, amt| { account: acct, amount: amt } }
    credits += legs[:taxes].map    { |tax, amt| { account: tax.liability_account, amount: amt } }
    { debits: [ { account: receivable_account, amount: document.total } ], credits: credits }
  end

  def ledger_description(document) = "Invoice ##{document.id} — #{document.counterparty}"

  # Money in: the bank goes up, receivables come down.
  def settlement_legs(bank_account) = [ bank_account.account, receivable_account ]
  def settlement_direction          = :received

  private

  def sync_client_name_from_contact
    self.client_name = document.contact.name if document&.contact && client_name.blank?
  end
end

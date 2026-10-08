class Invoice < ApplicationRecord
  include Documentable

  belongs_to :receivable_account, class_name: "Plutus::Asset"

  DEFAULT_PREFIX = "INV-".freeze

  before_validation :sync_client_name_from_contact
  before_validation :assign_number, on: :create
  after_save :advance_sequence, if: :saved_change_to_number?
  validates :client_name, :due_date, :number, presence: true
  validate  :number_unique_in_organization
  scoped_to_organization :receivable_account, organization: ->(i) { i.document&.organization }

  # The next number in the organisation's sequence; Settings owns the prefix
  # and the counter, so numbers under other prefixes never steer it.
  def self.next_number(organization) = organization.settings.next_invoice_number

  def party_name  = client_name
  def settleable? = true
  def draftable?  = true

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

  def ledger_description(document) = "Invoice #{number} — #{document.counterparty}"

  # Money in: the bank goes up, receivables come down.
  def settlement_legs(bank_account) = [ bank_account.account, receivable_account ]
  def settlement_direction          = :received

  private

  def assign_number
    self.number = self.class.next_number(document.organization) if number.blank? && document&.organization
  end

  def advance_sequence
    document&.organization&.settings&.advance_invoice_sequence!(number)
  end

  def number_unique_in_organization
    return if number.blank? || document.nil?
    clash = Invoice.joins(:document).where(documents: { organization_id: document.organization_id }, number: number).where.not(id: id)
    errors.add(:number, "#{number} is already used") if clash.exists?
  end

  def sync_client_name_from_contact
    self.client_name = document.contact.name if document&.contact && client_name.blank?
  end
end

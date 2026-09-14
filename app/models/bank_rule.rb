# "When a line looks like this, it is that": a pattern over payee/description
# plus what to create for it. Rules suggest by default; auto_apply lets a
# trusted rule categorize straight from an import.
class BankRule < ApplicationRecord
  MATCH_KINDS  = %w[contains starts_with regex].freeze
  AMOUNT_SIGNS = %w[any in out].freeze
  ACTIONS      = %w[Expense Deposit Transfer].freeze
  REGEX_TIMEOUT = 0.05

  belongs_to :organization
  belongs_to :bank_account, optional: true
  belongs_to :contact,      optional: true
  belongs_to :tax_rate,     optional: true
  belongs_to :account,      class_name: "Plutus::Account", optional: true
  belongs_to :transfer_bank_account, class_name: "BankAccount", optional: true
  has_many   :bank_transactions, dependent: :nullify

  validates :name, :pattern, presence: true
  validates :pattern, length: { maximum: 200 }
  validates :match_kind,  inclusion: { in: MATCH_KINDS }
  validates :amount_sign, inclusion: { in: AMOUNT_SIGNS }
  validates :action_kind, inclusion: { in: ACTIONS }
  validate  :action_has_a_target
  validate  :references_stay_in_organization
  validate  :regex_compiles, if: -> { match_kind == "regex" }

  scope :active,  -> { where(active: true) }
  scope :ordered, -> { order(:position, :id) }

  def self.first_match(txn)
    active.ordered.detect { |rule| rule.matches?(txn) }
  end

  def matches?(txn)
    return false if bank_account_id && txn.bank_account_id != bank_account_id
    return false if amount_sign == "in"  && !txn.deposit?
    return false if amount_sign == "out" && !txn.withdrawal?
    hay = [ txn.payee, txn.description ].compact_blank.join(" ").downcase
    case match_kind
    when "contains"    then hay.include?(pattern.downcase)
    when "starts_with" then hay.start_with?(pattern.downcase)
    when "regex"       then regexp.match?(hay)
    end
  rescue RegexpError, Regexp::TimeoutError
    false
  end

  def regexp = Regexp.new(pattern, Regexp::IGNORECASE, timeout: REGEX_TIMEOUT)

  def summary
    case action_kind
    when "Transfer" then "Transfer with #{transfer_bank_account&.name}"
    else "#{action_kind}: #{account&.name}#{contact ? " · #{contact.name}" : ''}"
    end
  end

  # Do what the rule says to this line.
  def apply!(txn, source: "reconcile")
    if action_kind == "Transfer"
      Reconciliation::CreateTransfer.new(txn, other_bank_account: transfer_bank_account, source: source).call
    else
      Reconciliation::Categorize.new(txn, account: account, tax_rate: tax_rate, contact_name: contact&.name, source: source).call
    end
  end

  private

  def action_has_a_target
    if action_kind == "Transfer"
      errors.add(:transfer_bank_account, "is required for a transfer rule") if transfer_bank_account.nil?
    elsif account.nil?
      errors.add(:account, "is required")
    end
  end

  def references_stay_in_organization
    errors.add(:bank_account, "must belong to this organization")          if bank_account && bank_account.organization_id != organization_id
    errors.add(:transfer_bank_account, "must belong to this organization") if transfer_bank_account && transfer_bank_account.organization_id != organization_id
    errors.add(:contact, "must belong to this organization")               if contact && contact.organization_id != organization_id
    errors.add(:tax_rate, "must belong to this organization")              if tax_rate && tax_rate.organization_id != organization_id
    errors.add(:account, "must belong to this organization")               if account && account.tenant_id != organization_id
  end

  def regex_compiles
    Regexp.new(pattern)
  rescue RegexpError => e
    errors.add(:pattern, "is not a valid regex (#{e.message})")
  end
end

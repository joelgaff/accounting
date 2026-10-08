# "When a line looks like this, it is that": one or more conditions on the
# line, all or any of which must hold, plus what to create for it. Direction
# and bank account are the rule's scope. Rules suggest by default; auto_apply
# lets a trusted rule categorize straight from an import.
class BankRule < ApplicationRecord
  include Trackable

  AMOUNT_SIGNS = %w[any in out].freeze
  ACTIONS      = %w[Expense Deposit Transfer].freeze

  belongs_to :organization
  belongs_to :bank_account, optional: true
  belongs_to :contact,      optional: true
  belongs_to :tax_rate,     optional: true
  belongs_to :account,      class_name: "Plutus::Account", optional: true
  belongs_to :transfer_bank_account, class_name: "BankAccount", optional: true
  has_many   :bank_transactions, dependent: :nullify
  has_many   :conditions, -> { order(:position, :id) }, class_name: "BankRuleCondition", dependent: :destroy, inverse_of: :bank_rule
  accepts_nested_attributes_for :conditions, allow_destroy: true, reject_if: ->(a) { a["value"].blank? && a["id"].blank? }

  # The old one-test shape, still accepted: pattern plus match_kind become the first condition.
  attr_writer :pattern, :match_kind
  before_validation :condition_from_pattern

  validates :name, presence: true
  validates :amount_sign, inclusion: { in: AMOUNT_SIGNS }
  validates :action_kind, inclusion: { in: ACTIONS }
  validate  :action_has_a_target
  validate  :references_stay_in_organization
  validate  :has_a_condition

  scope :active,  -> { where(active: true) }
  scope :ordered, -> { order(:position, :id) }

  def self.first_match(txn)
    active.ordered.detect { |rule| rule.matches?(txn) }
  end

  def matches?(txn)
    return false if bank_account_id && txn.bank_account_id != bank_account_id
    return false if amount_sign == "in"  && !txn.deposit?
    return false if amount_sign == "out" && !txn.withdrawal?
    live = conditions.reject(&:marked_for_destruction?)
    return false if live.empty?
    match_all? ? live.all? { |c| c.holds_for?(txn) } : live.any? { |c| c.holds_for?(txn) }
  end

  # "payee or description contains “lyft” and amount more than 20.00"
  def when_summary
    conditions.reject(&:marked_for_destruction?).map(&:to_sentence).join(match_all? ? " and " : " or ")
  end

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
      Reconciliation::Categorize.new(txn, account: account, tax_rate: tax_rate, contact_name: contact&.name,
                                     tracking_option_ids: tracking_option_ids, source: source).call
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

  def condition_from_pattern
    return if @pattern.blank?
    conditions.build(field: "text", operator: @match_kind.presence || "contains", value: @pattern) if conditions.empty?
    @pattern = nil
  end

  def has_a_condition
    errors.add(:conditions, "need at least one") if conditions.reject(&:marked_for_destruction?).empty?
  end
end

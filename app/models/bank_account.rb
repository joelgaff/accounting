# A bank account the way Xero models one: a chart-of-accounts entry (the
# ledger `account`) plus the details only banks carry. Checking and savings
# sit in assets; a credit card is a liability, so its ledger account flips
# class when the kind changes.
class BankAccount < ApplicationRecord
  KINDS = %w[checking savings credit_card].freeze
  LEDGER_CLASS = {
    "checking"    => "Plutus::Asset",
    "savings"     => "Plutus::Asset",
    "credit_card" => "Plutus::Liability"
  }.freeze

  belongs_to :organization
  belongs_to :account, class_name: "Plutus::Account", autosave: true
  belongs_to :bank_feed, optional: true
  has_many   :payments,          dependent: :restrict_with_error
  has_many   :expenses,          dependent: :restrict_with_error
  has_many   :deposits,          dependent: :restrict_with_error
  has_many   :bank_rules,        dependent: :nullify
  has_many   :transfers_out, class_name: "Transfer", foreign_key: :from_bank_account_id, dependent: :restrict_with_error, inverse_of: :from_bank_account
  has_many   :transfers_in,  class_name: "Transfer", foreign_key: :to_bank_account_id,   dependent: :restrict_with_error, inverse_of: :to_bank_account
  has_many   :bank_transactions, dependent: :restrict_with_error

  validates :kind,      inclusion: { in: KINDS }
  validates :last_four, format: { with: /\A\d{4}\z/, message: "must be four digits" }, allow_blank: true
  validate  :account_belongs_to_organization

  before_validation :align_ledger_class

  scope :active,   -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :ordered,  -> { joins(:account).order(Plutus::Account.arel_table[:code], Plutus::Account.arel_table[:name]) }

  # Xero names a bank by its chart code or its name; accept either.
  def self.find_by_code_or_name(key)
    joins(:account).find_by(plutus_accounts: { code: key }) || joins(:account).find_by(plutus_accounts: { name: key })
  end

  delegate :name, :code, :description, :balance, :name=, :code=, :description=, to: :account

  # Built lazily so `BankAccount.new(name: "Chase")` has somewhere to put the name.
  def account
    super || build_account(type: LEDGER_CLASS.fetch(kind), tenant: organization, xero_type: "BANK")
  end

  # Xero exports every bank account as plain "Bank"; the name is the only hint
  # of what it really is. Used when an import creates one.
  def self.guess_kind(name)
    case name.to_s
    when /card|visa|mastercard|amex|discover/i then "credit_card"
    when /saving/i                               then "savings"
    else "checking"
    end
  end

  def credit_card? = kind == "credit_card"
  def archived?    = archived_at.present?
  def kind_label   = kind.humanize
  def display_name = code.present? ? "#{code} — #{name}" : name

  def archive!  = update!(archived_at: Time.current)
  def restore!  = update!(archived_at: nil)

  private

  def align_ledger_class
    account.tenant ||= organization
    account.xero_type ||= "BANK"
    account.code = nil if account.code.blank?   # the chart's unique code index treats "" as a value
    wanted = LEDGER_CLASS.fetch(kind, LEDGER_CLASS["checking"])
    return if account.type == wanted

    if account.new_record?
      attrs = account.attributes.except("id", "type")
      self.account = wanted.constantize.new(attrs)
    else
      account.type = wanted
    end
  end

  def account_belongs_to_organization
    return if organization.nil? || account.tenant_id.nil? || account.tenant_id == organization.id
    errors.add(:account, "must belong to this organization")
  end
end

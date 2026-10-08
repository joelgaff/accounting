# One test on one field of a statement line. Text fields take contains,
# starts_with, equals and regex; the amount takes equals, more_than,
# less_than and between, and always compares the size of the amount, since
# direction is the rule's own scope.
class BankRuleCondition < ApplicationRecord
  FIELDS         = %w[text payee description reference amount].freeze
  TEXT_OPERATORS = %w[contains starts_with equals regex].freeze
  AMOUNT_OPERATORS = %w[equals more_than less_than between].freeze
  REGEX_TIMEOUT  = 0.05

  FIELD_LABELS = { "text" => "payee or description", "payee" => "payee", "description" => "description",
                   "reference" => "reference", "amount" => "amount" }.freeze
  OPERATOR_LABELS = { "contains" => "contains", "starts_with" => "starts with", "equals" => "is", "regex" => "matches",
                      "more_than" => "more than", "less_than" => "less than", "between" => "between" }.freeze

  belongs_to :bank_rule, inverse_of: :conditions

  before_validation :normalize_amounts, if: :amount?

  validates :field,    inclusion: { in: FIELDS }
  validates :value,    presence: true, length: { maximum: 200 }
  validate  :operator_suits_field
  validate  :amounts_are_numbers, if: :amount?
  validate  :regex_compiles,      if: -> { operator == "regex" }

  def amount? = field == "amount"

  def holds_for?(txn)
    amount? ? amount_holds?(txn.amount.abs) : text_holds?(text_of(txn))
  rescue RegexpError, Regexp::TimeoutError
    false
  end

  def to_sentence
    "#{FIELD_LABELS[field]} #{OPERATOR_LABELS[operator]} " +
      (amount? ? [ money(value), (money(value_to) if operator == "between") ].compact.join(" and ") : "“#{value}”")
  end

  private

  def text_of(txn)
    case field
    when "text"        then [ txn.payee, txn.description ].compact_blank.join(" ")
    when "payee"       then txn.payee.to_s
    when "description" then txn.description.to_s
    when "reference"   then txn.reference.to_s
    end.downcase
  end

  def text_holds?(hay)
    needle = value.downcase
    case operator
    when "contains"    then hay.include?(needle)
    when "starts_with" then hay.start_with?(needle)
    when "equals"      then hay == needle
    when "regex"       then Regexp.new(value, Regexp::IGNORECASE, timeout: REGEX_TIMEOUT).match?(hay)
    end
  end

  def amount_holds?(size)
    low = BigDecimal(value.to_s)
    case operator
    when "equals"    then size == low
    when "more_than" then size > low
    when "less_than" then size < low
    when "between"   then size.between?(low, BigDecimal(value_to.to_s))
    end
  end

  def money(v) = format("%.2f", BigDecimal(v.to_s)) rescue v.to_s

  def operator_suits_field
    allowed = amount? ? AMOUNT_OPERATORS : TEXT_OPERATORS
    errors.add(:operator, "#{OPERATOR_LABELS[operator] || operator} does not apply to #{FIELD_LABELS[field] || field}") unless allowed.include?(operator)
  end

  # "$1,000.50" is a number too.
  def normalize_amounts
    self.value    = value.to_s.delete("$, ").presence
    self.value_to = value_to.to_s.delete("$, ").presence
  end

  def amounts_are_numbers
    [ value, (value_to if operator == "between") ].compact.each do |v|
      Float(v)
    rescue ArgumentError, TypeError
      errors.add(:value, "must be a number")
    end
    if operator == "between"
      errors.add(:value_to, "is needed for between") if value_to.blank?
      errors.add(:value, "and the second value must run low to high") if value_to.present? && errors.empty? && BigDecimal(value) > BigDecimal(value_to)
    end
  end

  def regex_compiles
    Regexp.new(value)
  rescue RegexpError => e
    errors.add(:value, "is not a valid regex (#{e.message})")
  end
end

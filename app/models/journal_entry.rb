class JournalEntry < ApplicationRecord
  include Documentable

  has_many :lines, -> { ordered }, class_name: "JournalLine", inverse_of: :journal_entry, dependent: :destroy
  accepts_nested_attributes_for :lines, allow_destroy: true, reject_if: :all_blank

  validates :narrative, presence: true
  validate  :must_have_at_least_two_lines
  validate  :debits_equal_credits

  def line_items? = false

  def total_debits  = live_lines.sum { |l| l.debit_amount.to_d }
  def total_credits = live_lines.sum { |l| l.credit_amount.to_d }
  def balanced?     = total_debits == total_credits

  def totals_for(_document) = [ total_debits, BigDecimal("0") ]

  def ledger_legs(_document)
    {
      debits:  live_lines.select(&:debit?).map  { |l| { account: l.account, amount: l.debit_amount } },
      credits: live_lines.select(&:credit?).map { |l| { account: l.account, amount: l.credit_amount } }
    }
  end

  def ledger_description(_document) = narrative

  private

  def live_lines = lines.reject(&:marked_for_destruction?)

  def must_have_at_least_two_lines
    errors.add(:base, "must have at least two lines") if live_lines.size < 2
  end

  def debits_equal_credits
    return if live_lines.size < 2
    errors.add(:base, "debits ($#{total_debits}) must equal credits ($#{total_credits})") unless balanced?
  end
end

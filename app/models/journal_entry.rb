class JournalEntry < ApplicationRecord
  belongs_to :organization
  has_many   :lines, -> { ordered }, class_name: "JournalLine", inverse_of: :journal_entry, dependent: :destroy
  has_many   :entries, class_name: "Plutus::Entry", as: :commercial_document

  accepts_nested_attributes_for :lines, allow_destroy: true, reject_if: :all_blank

  validates :posted_on, :narrative, presence: true
  validate  :must_have_at_least_two_lines
  validate  :debits_equal_credits

  after_create :post_to_ledger

  def total_debits  = lines.sum { |l| l.debit_amount.to_d }
  def total_credits = lines.sum { |l| l.credit_amount.to_d }
  def balanced?     = total_debits == total_credits

  private

  def must_have_at_least_two_lines
    errors.add(:base, "must have at least two lines") if lines.reject(&:marked_for_destruction?).size < 2
  end

  def debits_equal_credits
    return if lines.reject(&:marked_for_destruction?).size < 2
    if !balanced?
      errors.add(:base, "debits ($#{total_debits}) must equal credits ($#{total_credits})")
    end
  end

  def post_to_ledger
    debits  = lines.select(&:debit?).map  { |l| { account: l.account, amount: l.debit_amount } }
    credits = lines.select(&:credit?).map { |l| { account: l.account, amount: l.credit_amount } }
    Ledger.post(
      description: narrative,
      date: posted_on,
      commercial_document: self,
      debits: debits,
      credits: credits
    )
  end
end

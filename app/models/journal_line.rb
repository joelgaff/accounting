class JournalLine < ApplicationRecord
  belongs_to :journal_entry, inverse_of: :lines
  belongs_to :account, class_name: "Plutus::Account"

  validates :debit_amount,  numericality: { greater_than_or_equal_to: 0 }
  validates :credit_amount, numericality: { greater_than_or_equal_to: 0 }
  validate  :one_side_only

  scope :ordered, -> { order(:position, :id) }

  def debit?  = debit_amount.to_d.positive?
  def credit? = credit_amount.to_d.positive?
  def amount  = debit? ? debit_amount : credit_amount

  private

  def one_side_only
    if debit_amount.to_d.positive? && credit_amount.to_d.positive?
      errors.add(:base, "line must be either a debit or a credit, not both")
    elsif debit_amount.to_d.zero? && credit_amount.to_d.zero?
      errors.add(:base, "line must have a debit or credit amount")
    end
  end
end

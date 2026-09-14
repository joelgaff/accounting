# One line from a bank statement. It is reconciled by the payments it settled
# (each pointing back here) and by at most one document created or chosen for
# it. Status flips to matched when the allocations cover the amount.
class BankTransaction < ApplicationRecord
  STATUSES = %w[unmatched matched ignored].freeze

  belongs_to :organization
  belongs_to :bank_account
  belongs_to :document,  optional: true
  belongs_to :bank_rule, optional: true            # the rule that suggested a category
  has_many   :payments,  dependent: :nullify

  validates :posted_on, :amount, presence: true
  validates :status,    inclusion: { in: STATUSES }

  scope :unmatched, -> { where(status: "unmatched") }
  scope :matched,   -> { where(status: "matched") }
  scope :ignored,   -> { where(status: "ignored") }

  def deposit?    = amount.positive?
  def withdrawal? = amount.negative?
  def direction   = deposit? ? "in" : "out"
  def unmatched?  = status == "unmatched"
  def ignored?    = status == "ignored"
  def matched?    = status == "matched"

  def display_payee = payee.presence || description

  def allocated = (payments.loaded? ? payments.sum(&:amount) : payments.sum(:amount)) + (document&.total || BigDecimal("0"))
  def remaining = amount.abs - allocated
  def partial?  = unmatched? && allocated.positive?

  # Made by the reconcile page for this very line, so Undo may remove it.
  def created_document? = document.present? && document.source == "reconcile"

  def refresh_status!
    return if ignored?
    update!(status: remaining.zero? ? "matched" : "unmatched")
  end

  # Drop the document link (a void, say) and recompute; payments are untouched.
  def unlink!
    update!(document: nil)
    refresh_status!
  end
end

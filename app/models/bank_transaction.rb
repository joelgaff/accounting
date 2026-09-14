class BankTransaction < ApplicationRecord
  STATUSES = %w[unmatched matched ignored].freeze

  belongs_to :organization
  belongs_to :bank_account
  belongs_to :matched,      polymorphic: true, optional: true

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

  # Link this line to what settles it: a Payment, or a Document created or chosen for it.
  def match_to!(record)
    update!(status: "matched", matched: record)
  end

  def unlink!
    update!(status: "unmatched", matched: nil)
  end

  def matched_document
    matched.is_a?(Document) ? matched : matched&.document
  end
end

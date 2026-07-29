class BankTransaction < ApplicationRecord
  STATUSES = %w[unmatched matched ignored].freeze

  belongs_to :organization
  belongs_to :bank_account, class_name: "Plutus::Asset"
  belongs_to :matched,      polymorphic: true, optional: true

  validates :posted_on, :amount, presence: true
  validates :status,    inclusion: { in: STATUSES }

  scope :unmatched, -> { where(status: "unmatched") }
  scope :matched,   -> { where(status: "matched") }
  scope :ignored,   -> { where(status: "ignored") }

  def deposit?    = amount.positive?
  def withdrawal? = amount.negative?
  def direction   = deposit? ? "in" : "out"
end

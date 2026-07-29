class Contact < ApplicationRecord
  KINDS = %w[customer vendor both].freeze

  belongs_to :organization
  has_many :invoices, dependent: :restrict_with_error
  has_many :expenses, dependent: :restrict_with_error

  validates :name, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP, allow_blank: true }

  scope :customers, -> { where(kind: %w[customer both]) }
  scope :vendors,   -> { where(kind: %w[vendor both]) }
  scope :ordered,   -> { order(:name) }

  def customer? = kind.in?(%w[customer both])
  def vendor?   = kind.in?(%w[vendor both])
end

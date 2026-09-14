class Contact < ApplicationRecord
  KINDS = %w[customer vendor both].freeze

  belongs_to :organization
  has_many :documents, dependent: :restrict_with_error

  validates :name, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP, allow_blank: true }

  # Find by name regardless of case, or create; a contact seen on both sides
  # of the books becomes "both".
  def self.find_or_create_named(organization, name, kind:)
    name = name.to_s.strip
    contact = organization.contacts.where("LOWER(name) = ?", name.downcase).first
    return organization.contacts.create!(name: name, kind: kind) unless contact
    contact.update!(kind: "both") if contact.kind != kind && contact.kind != "both"
    contact
  end

  scope :customers, -> { where(kind: %w[customer both]) }
  scope :vendors,   -> { where(kind: %w[vendor both]) }
  scope :ordered,   -> { order(:name) }

  def customer? = kind.in?(%w[customer both])
  def vendor?   = kind.in?(%w[vendor both])
end

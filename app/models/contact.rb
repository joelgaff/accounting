class Contact < ApplicationRecord
  KINDS = %w[customer vendor both].freeze

  belongs_to :organization
  has_many :documents, dependent: :restrict_with_error

  validates :name, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP, allow_blank: true }

  # Find by name regardless of case, or create; a contact seen on both sides
  # of the books becomes "both".
  # Name, email or phone containing the text, case aside. LIKE's own
  # wildcards are escaped, so "%" is a character nobody is named.
  scope :matching, ->(text) {
    pattern = "%#{sanitize_sql_like(text.to_s.strip)}%"
    where("contacts.name LIKE :p ESCAPE '\\' OR contacts.email LIKE :p ESCAPE '\\' OR contacts.phone LIKE :p ESCAPE '\\'", p: pattern)
  }

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

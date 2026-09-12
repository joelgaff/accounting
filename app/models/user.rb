class User < ApplicationRecord
  belongs_to :organization

  validates :launchpad_public_id, presence: true, uniqueness: true

  # email_address is synced display data from Launchpad, not an identifier.
  # `email` kept as an alias so existing views/callers keep working.
  alias_attribute :email, :email_address
end

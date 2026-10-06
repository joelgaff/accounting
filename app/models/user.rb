class User < ApplicationRecord
  THEMES   = %w[dark light].freeze
  CODE_TTL = 10.minutes
  CODE_ATTEMPTS = 5          # wrong guesses before the code is void
  SEND_WINDOW   = 15.minutes # at most SENDS_PER_WINDOW codes per address in it
  SENDS_PER_WINDOW = 3

  belongs_to :organization

  normalizes :email_address, with: ->(e) { e.to_s.strip.downcase }

  validates :launchpad_public_id, uniqueness: true, allow_nil: true
  validates :email_address, presence: true
  validates :email_address, uniqueness: { case_sensitive: false, conditions: -> { where(launchpad_public_id: nil) } }, if: :local?
  validates :theme, inclusion: { in: THEMES }

  # email_address is synced display data from Launchpad, not an identifier.
  # `email` kept as an alias so existing views/callers keep working.
  alias_attribute :email, :email_address

  scope :local, -> { where(launchpad_public_id: nil) }

  def local? = launchpad_public_id.nil?

  # ── Magic-code sign-in (local mode), the rails-now way ─────────────────────

  # Generate a 6-digit code, store its digest, return the plaintext to email.
  # Raises when the address has asked too often; the caller shows the same
  # page either way so nothing leaks.
  def issue_login_code!
    raise TooManyRequests if login_code_throttled?
    code  = format("%06d", SecureRandom.random_number(1_000_000))
    sends = login_code_sent_at && login_code_sent_at > SEND_WINDOW.ago ? login_code_sends + 1 : 1
    update!(
      login_code_digest:     BCrypt::Password.create(code),
      login_code_expires_at: CODE_TTL.from_now,
      login_code_attempts:   0,
      login_code_sent_at:    Time.current,
      login_code_sends:      sends
    )
    code
  end

  # True once, for a live code; every wrong guess counts and the fifth voids it.
  def login_code_valid?(submitted)
    return false if login_code_digest.blank? || login_code_expires_at.blank? || login_code_expires_at.past?
    return false if login_code_attempts >= CODE_ATTEMPTS
    if BCrypt::Password.new(login_code_digest) == submitted.to_s.strip
      true
    else
      increment!(:login_code_attempts)
      false
    end
  end

  def clear_login_code!
    update!(login_code_digest: nil, login_code_expires_at: nil, login_code_attempts: 0)
  end

  def login_code_throttled?
    login_code_sent_at.present? && login_code_sent_at > SEND_WINDOW.ago && login_code_sends >= SENDS_PER_WINDOW
  end

  class TooManyRequests < StandardError; end
end

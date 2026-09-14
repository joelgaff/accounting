# A connection to a bank data provider (SimpleFIN today). Holds the access
# credential, the provider's list of accounts, and how the last sync went.
class BankFeed < ApplicationRecord
  PROVIDERS   = %w[simplefin].freeze
  MIN_GAP     = 10.minutes   # SimpleFIN allows about 24 requests a day

  belongs_to :organization
  has_many   :bank_accounts, dependent: :nullify

  encrypts :access_url

  validates :provider, inclusion: { in: PROVIDERS }
  validates :access_url, presence: true

  def client = SimpleFin::Client.new(access_url)

  def sync_allowed? = last_synced_at.nil? || last_synced_at < MIN_GAP.ago

  # Provider accounts not yet mapped to one of ours.
  def unmapped_accounts
    mapped = bank_accounts.pluck(:feed_account_id)
    accounts.reject { |a| mapped.include?(a["id"]) }
  end

  def summary
    return nil if last_summary.blank?
    JSON.parse(last_summary)
  rescue JSON::ParserError
    nil
  end
end

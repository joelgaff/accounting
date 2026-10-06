# The organisation's link to its Xero organisation: OAuth tokens (encrypted),
# the tenant they unlock, and how the last import went. One per organisation.
class XeroConnection < ApplicationRecord
  STATUSES = %w[idle running done failed].freeze

  belongs_to :organization

  encrypts :access_token, :refresh_token

  validates :tenant_id, :access_token, :refresh_token, :token_expires_at, presence: true
  validates :status, inclusion: { in: STATUSES }

  def client = Xero::Client.new(self)

  def running? = status == "running"
  def token_expired? = token_expires_at <= 1.minute.from_now

  # Progress is a list of steps the import has finished or is on.
  def steps
    JSON.parse(progress.presence || "[]")
  rescue JSON::ParserError
    []
  end

  def summary
    JSON.parse(last_summary.presence || "null")
  rescue JSON::ParserError
    nil
  end

  def record_step!(name, result = nil)
    list = steps.reject { |s| s["step"] == name }
    list << { "step" => name, "created" => result&.created, "updated" => result&.updated, "skipped" => result&.skipped,
              "errors" => result&.errors.to_a.first(20), "done" => result.present? }
    update!(progress: list.to_json)
  end
end

# Nightly pull of every organisation's bank feed (see config/recurring.yml).
class SimpleFinSyncJob < ApplicationJob
  queue_as :default

  def perform(bank_feed_id = nil)
    scope = bank_feed_id ? BankFeed.where(id: bank_feed_id) : BankFeed.all
    scope.includes(:organization).find_each do |feed|
      Current.organization = feed.organization
      SimpleFin::Sync.new(feed).call
    rescue => e
      Rails.logger.error("[SimpleFinSyncJob] feed #{feed.id}: #{e.class}: #{e.message}")   # last_error already records it
    ensure
      Current.reset
    end
  end
end

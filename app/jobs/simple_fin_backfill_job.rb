# Runs a bank feed backfill in the background; progress lands on the feed.
class SimpleFinBackfillJob < ApplicationJob
  queue_as :default

  def perform(bank_feed_id, from)
    feed = BankFeed.find(bank_feed_id)
    Current.organization = feed.organization
    SimpleFin::Backfill.new(feed, from: Date.parse(from.to_s)).call
  rescue SimpleFin::Error, SocketError, Timeout::Error, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError => e
    Rails.logger.error("[SimpleFinBackfillJob] feed #{bank_feed_id}: #{e.class}: #{e.message}")   # recorded on the feed already
  ensure
    Current.reset
  end
end

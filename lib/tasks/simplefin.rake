# SimpleFIN beyond the nightly sync.
#
#   bin/rails 'simplefin:backfill[2025-01-01]'     pull history from that date in 90-day windows
#   bin/rails simplefin:sync                       one sync now (what the nightly job does)
#
# ORG_ID=n picks the organisation; otherwise the single one. SimpleFIN allows
# about 24 requests a day, so a backfill stops after MAX_WINDOWS and prints
# where to resume; lines already imported dedupe on the bank's own ids.
namespace :simplefin do
  MAX_WINDOWS = 20

  def simplefin_feed
    org = ENV["ORG_ID"].present? ? Organization.find(ENV["ORG_ID"]) : Organization.sole
    Current.organization = org
    org.bank_feed or abort "#{org.name} has no bank feed; connect SimpleFIN under Settings first."
  end

  desc "Backfill bank lines from a date (YYYY-MM-DD) in 90-day windows; stops after #{MAX_WINDOWS} windows"
  task :backfill, [ :from ] => :environment do |_, args|
    from = Date.parse(args[:from].to_s) rescue abort("usage: bin/rails 'simplefin:backfill[YYYY-MM-DD]'")
    feed = simplefin_feed
    step = SimpleFin::Client::MAX_RANGE_DAYS - 1
    windows = 0
    cursor = from
    while cursor <= Date.current && windows < MAX_WINDOWS
      finish = [ cursor + step, Date.current ].min
      summary = SimpleFin::Sync.new(feed, from: cursor, to: finish).call
      puts format("  %s .. %s  imported %-4d duplicates %-4d%s", cursor, finish, summary.imported, summary.duplicates,
                  summary.errors.any? ? "  errors: #{summary.errors.join('; ')}" : "")
      windows += 1
      cursor = finish + 1
    end
    puts(cursor <= Date.current ? "Stopped after #{MAX_WINDOWS} windows; resume tomorrow with bin/rails 'simplefin:backfill[#{cursor}]'" : "Backfill complete.")
  end

  desc "Sync the bank feed now"
  task sync: :environment do
    feed = simplefin_feed
    summary = SimpleFin::Sync.new(feed).call
    puts "accounts #{summary.accounts}  imported #{summary.imported}  duplicates #{summary.duplicates}  rules applied #{summary.rules_applied}"
    puts "unmapped: #{summary.unmapped.join(', ')}" if summary.unmapped.any?
    puts "errors: #{summary.errors.join('; ')}" if summary.errors.any?
  end
end

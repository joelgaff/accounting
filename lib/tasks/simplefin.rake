# SimpleFIN beyond the nightly sync.
#
#   bin/rails 'simplefin:backfill[2025-01-01]'     pull history from that date in 90-day windows
#   bin/rails simplefin:sync                       one sync now (what the nightly job does)
#
# ORG_ID=n picks the organisation; otherwise the single one. SimpleFIN allows
# about 24 requests a day, so a backfill stops after 20 windows and prints
# where to resume; lines already imported dedupe on the bank's own ids.
namespace :simplefin do
  def simplefin_feed
    org = ENV["ORG_ID"].present? ? Organization.find(ENV["ORG_ID"]) : Organization.sole
    Current.organization = org
    org.bank_feed or abort "#{org.name} has no bank feed; connect SimpleFIN under Settings first."
  end

  desc "Backfill bank lines from a date (YYYY-MM-DD) in 90-day windows; stops after 20 windows a day"
  task :backfill, [ :from ] => :environment do |_, args|
    from = Date.parse(args[:from].to_s) rescue abort("usage: bin/rails 'simplefin:backfill[YYYY-MM-DD]'")
    result = SimpleFin::Backfill.new(simplefin_feed, from: from).call
    result[:windows].each do |w|
      puts format("  %s .. %s  imported %-4d duplicates %-4d%s", w.from, w.to, w.imported, w.duplicates, w.errors.any? ? "  errors: #{w.errors.join('; ')}" : "")
    end
    puts(result[:resume] ? "Stopped after #{SimpleFin::Backfill::MAX_WINDOWS} windows; resume tomorrow with bin/rails 'simplefin:backfill[#{result[:resume]}]'" : "Backfill complete.")
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

require "test_helper"

class SimpleFin::SyncTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @feed     = @org.create_bank_feed!(access_url: "https://u:p@bridge.simplefin.org/simplefin")
    @checking = create_bank_account(@org, name: "Checking")
    @checking.update!(bank_feed: @feed, feed_account_id: "ACT-checking-4821", feed_name: "Business Checking 4821")
    @hosting  = Plutus::Expense.create!(tenant: @org, name: "Hosting")
    @client   = Object.new
    payload   = SimpleFin::Client.new("https://u:p@x.example/simplefin", transport: ->(*) { Struct.new(:code, :body) { def is_a?(k) = k == Net::HTTPSuccess }.new("200", file_fixture("simplefin/accounts.json").read) }).accounts(start_date: Date.current - 1)
    @client.define_singleton_method(:accounts) { |**| payload }
  end

  test "imports mapped accounts, skips pending, records balances and unmapped names, idempotently" do
    @org.bank_rules.create!(name: "CF", pattern: "cloudflare", action_kind: "Expense", account: @hosting, auto_apply: true)
    summary = SimpleFin::Sync.new(@feed, client: @client).call

    assert_equal 1, summary.accounts
    assert_equal 2, summary.imported
    assert_equal 1, summary.rules_applied
    assert_equal [ "Cash Rewards Card 2068" ], summary.unmapped
    assert_equal 2, @checking.bank_transactions.count
    assert @checking.bank_transactions.find_by(external_id: "TXN-1").matched?
    assert_equal "Cloudflare", @checking.bank_transactions.find_by(external_id: "TXN-1").payee
    assert_equal BigDecimal("4321.55"), @checking.reload.statement_balance
    assert @feed.reload.last_synced_at.present?
    assert_equal 2, @feed.accounts.size
    assert_equal 2, @feed.summary["imported"]

    again = SimpleFin::Sync.new(@feed, client: @client).call
    assert_equal 0, again.imported
    assert_equal 2, again.duplicates
    assert_equal 2, @checking.bank_transactions.count
  end

  test "a feed error is recorded on the feed and re-raised" do
    failing = Object.new
    failing.define_singleton_method(:accounts) { |**| raise SimpleFin::Error, "SimpleFIN returned 402" }
    assert_raises(SimpleFin::Error) { SimpleFin::Sync.new(@feed, client: failing).call }
    assert_match(/402/, @feed.reload.last_error)
  end

  test "the job walks every feed and swallows one feed's failure" do
    failing = Object.new
    failing.define_singleton_method(:accounts) { |**| raise SimpleFin::Error, "down" }
    stub_method(SimpleFin::Client, :new, ->(*) { failing }) do
      assert_nothing_raised { SimpleFinSyncJob.new.perform }
    end
    assert_match(/down/, @feed.reload.last_error)
    assert_nil Current.organization
  end

  test "access URL is encrypted at rest and never echoed" do
    raw = BankFeed.connection.select_value("SELECT access_url FROM bank_feeds WHERE id = #{@feed.id}")
    assert_not_includes raw, "bridge.simplefin.org"
    assert_equal "https://u:p@bridge.simplefin.org/simplefin", @feed.reload.access_url
  end
end

class SimpleFin::BackfillTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @feed     = @org.create_bank_feed!(access_url: "https://u:p@bridge.simplefin.org/simplefin")
    @checking = create_bank_account(@org, name: "Checking")
    @checking.update!(bank_feed: @feed, feed_account_id: "ACT-checking-4821", feed_name: "Business Checking 4821", statement_balance: 999, feed_synced_at: Time.current)
    @feed.update!(last_synced_at: Time.current)
    @client = Object.new
    windows = @windows = []
    payload = SimpleFin::Client.new("https://u:p@x.example/simplefin", transport: ->(*) { Struct.new(:code, :body) { def is_a?(k) = k == Net::HTTPSuccess }.new("200", file_fixture("simplefin/accounts.json").read) }).accounts(start_date: Date.current - 1)
    @client.define_singleton_method(:accounts) { |start_date:, end_date:, **| windows << [ start_date, end_date ]; payload }
  end

  test "a pinned window imports history without touching the feed's sync marker or balances" do
    before = @feed.last_synced_at
    summary = SimpleFin::Sync.new(@feed, client: @client, from: Date.new(2025, 1, 1), to: Date.new(2025, 3, 31)).call
    assert_equal [ [ Date.new(2025, 1, 1), Date.new(2025, 3, 31) ] ], @windows
    assert_equal 2, summary.imported
    assert_equal before, @feed.reload.last_synced_at
    assert_equal BigDecimal("999"), @checking.reload.statement_balance
  end
end

class SimpleFin::BackfillServiceTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @feed     = @org.create_bank_feed!(access_url: "https://u:p@bridge.simplefin.org/simplefin")
    @checking = create_bank_account(@org, name: "Checking")
    @checking.update!(bank_feed: @feed, feed_account_id: "ACT-checking-4821", feed_name: "Business Checking 4821")
    windows = @windows = []
    payload = SimpleFin::Client.new("https://u:p@x.example/simplefin", transport: ->(*) { Struct.new(:code, :body) { def is_a?(k) = k == Net::HTTPSuccess }.new("200", file_fixture("simplefin/accounts.json").read) }).accounts(start_date: Date.current - 1)
    @client = Object.new
    @client.define_singleton_method(:accounts) { |start_date:, end_date:, **| windows << [ start_date, end_date ]; payload }
  end

  test "walks 90-day windows to today and records each on the feed" do
    result = SimpleFin::Backfill.new(@feed, from: Date.current - 200, client: @client).call
    assert_equal 3, @windows.size
    assert_equal Date.current - 200, @windows.first.first
    assert_equal Date.current, @windows.last.last
    assert_nil result[:resume]
    b = @feed.reload.backfill
    assert_equal 3, b["windows"].size
    assert_equal 2, b["imported"], "the fixture's two lines land once, later windows see duplicates"
    assert_equal 2, b["windows"].last["duplicates"]
    assert @feed.backfill_finished_at.present?
    assert_not @feed.backfill_running?
  end

  test "stops at the daily window cap and says where to resume" do
    result = SimpleFin::Backfill.new(@feed, from: Date.current - (89 * 25), client: @client).call
    assert_equal SimpleFin::Backfill::MAX_WINDOWS, @windows.size
    assert_equal @windows.last.last + 1, result[:resume]
    assert_equal result[:resume].iso8601, @feed.reload.backfill["resume"]
  end

  test "a feed error is recorded and the run ends" do
    failing = Object.new
    failing.define_singleton_method(:accounts) { |**| raise SimpleFin::Error, "SimpleFIN returned 402" }
    assert_raises(SimpleFin::Error) { SimpleFin::Backfill.new(@feed, from: Date.current - 10, client: failing).call }
    assert_match(/402/, @feed.reload.backfill["error"])
    assert_not @feed.backfill_running?
  end
end

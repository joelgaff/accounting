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

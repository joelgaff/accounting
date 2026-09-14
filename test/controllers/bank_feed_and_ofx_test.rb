require "test_helper"

class BankFeedAndOfxTest < ActionDispatch::IntegrationTest
  setup do
    @org = organizations(:one)
    sign_in_as_launchpad_user(@org)
    @checking = create_bank_account(@org, name: "Checking", code: "090")
    @checking.update!(last_four: "4821")
    @card     = create_bank_account(@org, name: "Card", kind: "credit_card")
  end

  test "an OFX upload picks the account by last four and records the statement balance" do
    post imports_bank_path, params: { file: fixture_file_upload("ofx/checking_sgml.qfx", "application/x-ofx") }
    assert_redirected_to bank_transactions_path(bank_account_id: @checking.id)
    assert_match(/Imported 3/, flash[:notice])
    assert_equal 3, @checking.bank_transactions.count
    assert_equal BigDecimal("4321.55"), @checking.reload.statement_balance
    assert_equal "CLOUDFLARE INC", @checking.bank_transactions.find_by(external_id: "2026090201").payee

    post imports_bank_path, params: { file: fixture_file_upload("ofx/checking_xml.ofx", "application/x-ofx") }
    assert_match(/duplicates skipped 3/, flash[:notice])
    assert_equal 3, @checking.bank_transactions.count
  end

  test "an OFX file for an unknown account asks for a choice, and a chosen account wins" do
    post imports_bank_path, params: { file: fixture_file_upload("ofx/creditcard_sgml.qfx", "application/x-ofx") }
    assert_response :unprocessable_entity
    assert_match(/2068/, response.body)
    post imports_bank_path, params: { file: fixture_file_upload("ofx/creditcard_sgml.qfx", "application/x-ofx"), bank_account_id: @card.id }
    assert_redirected_to bank_transactions_path(bank_account_id: @card.id)
    assert_equal 2, @card.bank_transactions.count
  end

  test "a CSV row is adopted by the feed row for the same line" do
    post imports_bank_path, params: { file: Rack::Test::UploadedFile.new(StringIO.new("Date,Description,Amount\n2026-09-05,ACME WIDGETS & CO,1250.00\n"), "text/csv", original_filename: "s.csv"), bank_account_id: @checking.id }
    assert_equal 1, @checking.bank_transactions.count
    post imports_bank_path, params: { file: fixture_file_upload("ofx/checking_sgml.qfx", "application/x-ofx") }
    assert_equal 3, @checking.bank_transactions.count
    assert_equal "2026090502", @checking.bank_transactions.find_by(amount: 1250).external_id
  end

  test "the bank feed page connects, maps accounts, syncs and disconnects" do
    get bank_feed_path
    assert_response :success
    assert_select "textarea[name=setup_token]"

    fake = Struct.new(:code, :body) { def is_a?(k) = k == Net::HTTPSuccess }
    calls = 0
    transport = lambda do |request, _uri|
      calls += 1
      request.is_a?(Net::HTTP::Post) ? fake.new("200", "https://u:p@bridge.simplefin.org/simplefin") : fake.new("200", file_fixture("simplefin/accounts.json").read)
    end
    real_client = SimpleFin::Client.new("https://u:p@bridge.simplefin.org/simplefin", transport: transport)
    stub_method(SimpleFin::Client, :claim, ->(*) { "https://u:p@bridge.simplefin.org/simplefin" }) do
      stub_method(SimpleFin::Client, :new, ->(*) { real_client }) do
        post bank_feed_path, params: { setup_token: Base64.strict_encode64("https://bridge.simplefin.org/simplefin/claim/x") }
        assert_redirected_to bank_feed_path
        feed = @org.reload.bank_feed
        assert_equal 2, feed.accounts.size

        get bank_feed_path
        assert_response :success
        assert_select "select[name='mapping[ACT-checking-4821]']"

        patch bank_feed_path, params: { mapping: { "ACT-checking-4821" => @checking.id, "ACT-card-2068" => "new" } }
        assert_redirected_to bank_feed_path
        assert_equal "ACT-checking-4821", @checking.reload.feed_account_id
        card = @org.bank_accounts.find_by(feed_account_id: "ACT-card-2068")
        assert_equal "credit_card", card.kind
        assert_equal "2068", card.last_four

        feed.update!(last_synced_at: 1.hour.ago)
        post sync_bank_feed_path, as: :turbo_stream
        assert_response :success
        assert_match(/target="#{ActionView::RecordIdentifier.dom_id(feed, :status)}"/, response.body)
        assert_equal 2, @checking.bank_transactions.count
        assert_equal 1, card.bank_transactions.count

        post sync_bank_feed_path, as: :turbo_stream
        assert_match(/try again/, response.body)

        delete bank_feed_path
        assert_nil @org.reload.bank_feed
        assert_equal 2, @checking.bank_transactions.count
      end
    end
  end
end

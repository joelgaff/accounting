require "test_helper"

class Xero::ClientTest < ActiveSupport::TestCase
  setup do
    @org  = organizations(:one)
    @fake = FakeXero.new
    @conn = @org.create_xero_connection!(tenant_id: "tenant-1", tenant_name: "EE", access_token: "at-0", refresh_token: "rt-0", token_expires_at: 1.hour.from_now)
  end

  # Pin the app keys regardless of what the real credentials hold.
  def with_app_credentials(&block)
    stub_method(Xero::Client, :client_id, -> { "cid" }) { stub_method(Xero::Client, :client_secret, -> { "csecret" }, &block) }
  end

  test "builds the consent url and swaps a code for tokens with basic auth" do
    with_app_credentials do
      url = Xero::Client.authorize_url(redirect_uri: "https://app.example/settings/xero/callback", state: "abc")
      assert_match(/client_id=cid/, url)
      assert_match(/accounting\.journals\.read/, url)
      assert_match(/state=abc/, url)

      tokens = Xero::Client.exchange_code("the-code", redirect_uri: "https://app.example/cb", transport: @fake)
      assert_equal "at-1", tokens[:access_token]
      assert_in_delta 1800, tokens[:expires_at] - Time.current, 5
      method, url, auth, _, body = @fake.calls.last
      assert_equal "POST", method
      assert_match(/identity\.xero\.com/, url)
      assert_equal "Basic #{Base64.strict_encode64('cid:csecret')}", auth
      assert_match(/grant_type=authorization_code/, body)
    end
  end

  test "refreshes an expired token before calling the api and sends the tenant header" do
    with_app_credentials do
      @conn.update!(token_expires_at: 1.minute.ago)
      client = Xero::Client.new(@conn, transport: @fake, pause: 0)
      accounts = client.get("Accounts", key: "Accounts")
      assert_equal 9, accounts.size
      assert_equal "at-1", @conn.reload.access_token, "tokens persisted after refresh"
      _, _, auth, tenant = @fake.calls.last
      assert_equal "Bearer at-1", auth
      assert_equal "tenant-1", tenant
    end
  end

  test "pages until a short page, walks journals by offset, and retries after a 429" do
    client = Xero::Client.new(@conn, transport: FakeXero.new(rate_limit_once: true), pause: 0)
    assert_equal 4, client.each_page("Contacts", key: "Contacts").to_a.size
    assert_equal [ 1, 2, 3 ], client.each_journal.map { |j| j["JournalNumber"] }
  end

  test "parses both of Xero's date shapes" do
    assert_equal Date.new(2019, 3, 14), Xero::Client.parse_date("/Date(1552521600000+0000)/")
    assert_equal Date.new(2019, 9, 13), Xero::Client.parse_date("2019-09-13T00:00:00")
    assert_nil Xero::Client.parse_date(nil)
  end
end

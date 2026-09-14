require "test_helper"

class SimpleFin::ClientTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:code, :body) do
    def is_a?(klass) = klass == Net::HTTPSuccess ? code.to_s.start_with?("2") : super
  end

  def transport(code: "200", body: "")
    @requests = []
    ->(request, uri) { @requests << [ request, uri ]; FakeResponse.new(code, body) }
  end

  test "claim decodes the setup token and POSTs it once" do
    token = Base64.strict_encode64("https://bridge.simplefin.org/simplefin/claim/abc123")
    url = SimpleFin::Client.claim(token, transport: transport(body: "https://user:pass@bridge.simplefin.org/simplefin\n"))
    assert_equal "https://user:pass@bridge.simplefin.org/simplefin", url
    request, uri = @requests.sole
    assert_kind_of Net::HTTP::Post, request
    assert_equal "/simplefin/claim/abc123", uri.path
  end

  test "claim rejects junk and a spent token" do
    assert_raises(SimpleFin::Error) { SimpleFin::Client.claim("not base64 at all", transport: transport) }
    token = Base64.strict_encode64("https://bridge.simplefin.org/simplefin/claim/abc123")
    assert_raises(SimpleFin::Error) { SimpleFin::Client.claim(token, transport: transport(code: "403")) }
  end

  test "accounts sends basic auth and epoch dates, and parses the response" do
    client = SimpleFin::Client.new("https://u%40x:p%23w@bridge.simplefin.org/simplefin", transport: transport(body: file_fixture("simplefin/accounts.json").read))
    response = client.accounts(start_date: Date.new(2026, 9, 1), end_date: Date.new(2026, 9, 10))
    request, uri = @requests.sole
    assert_equal "/simplefin/accounts", uri.path
    assert_equal Date.new(2026, 9, 1).to_time.to_i.to_s, Rack::Utils.parse_query(uri.query)["start-date"]
    assert_equal "Basic #{Base64.strict_encode64('u@x:p#w')}", request["Authorization"]

    assert_equal 2, response.accounts.size
    checking = response.accounts.first
    assert_equal "ACT-checking-4821", checking.id
    assert_equal BigDecimal("4321.55"), checking.balance
    assert_equal 3, checking.transactions.size
    assert_equal Date.new(2026, 9, 2), checking.transactions.first.posted_on
    assert_equal "Cloudflare", checking.transactions.first.payee
    assert checking.transactions.last.pending
  end

  test "accounts refuses ranges over 90 days and non-2xx answers" do
    client = SimpleFin::Client.new("https://u:p@bridge.simplefin.org/simplefin", transport: transport(code: "402", body: ""))
    assert_raises(SimpleFin::Error) { client.accounts(start_date: Date.current - 100) }
    err = assert_raises(SimpleFin::Error) { client.accounts(start_date: Date.current - 10) }
    assert_match(/402/, err.message)
  end
end

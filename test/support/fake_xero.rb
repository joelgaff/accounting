# A Xero API stand-in: routes each request to a fixture by path, records what
# was asked, and can answer 429 once to prove the retry.
class FakeXero
  Response = Struct.new(:code, :body, :headers) do
    def is_a?(klass) = klass == Net::HTTPSuccess ? code == "200" : super
    def [](h) = headers.to_h[h]
  end

  attr_reader :calls

  def initialize(rate_limit_once: false)
    @calls = []
    @rate_limit_once = rate_limit_once
  end

  def to_proc = method(:call).to_proc

  def call(request, uri)
    @calls << [ request.method, uri.to_s, request["Authorization"], request["xero-tenant-id"], (request.body if request.method == "POST") ]
    if @rate_limit_once
      @rate_limit_once = false
      return Response.new("429", "", { "Retry-After" => "1" })
    end
    case uri.to_s
    when %r{identity\.xero\.com/connect/token}
      Response.new("200", { access_token: "at-#{@calls.size}", refresh_token: "rt-#{@calls.size}", expires_in: 1800 }.to_json, {})
    when %r{api\.xero\.com/connections}
      Response.new("200", [ { "tenantId" => "tenant-1", "tenantName" => "Endurance Evolution, LLC", "tenantType" => "ORGANISATION" } ].to_json, {})
    when %r{/Invoices\?}
      where = CGI.unescape(uri.query.to_s)
      type  = where[/Type=="(ACC\w+)"/, 1]
      page  = uri.query[/page=(\d+)/, 1].to_i
      return Response.new("200", { "Invoices" => [] }.to_json, {}) if page > 1
      invoices = JSON.parse(fixture("invoices_#{type.to_s.downcase}").body)["Invoices"]
      if (m = where.match(/Date>=DateTime\((\d+),(\d+),(\d+)\)/))   # Xero applies the where clause server-side
        floor = Date.new(m[1].to_i, m[2].to_i, m[3].to_i)
        invoices = invoices.select { |i| Date.parse(i["DateString"]) >= floor }
      end
      Response.new("200", { "Invoices" => invoices }.to_json, {})
    when %r{/BankTransfers}
      dated("BankTransfers", "banktransfers", uri, "Date")
    when %r{/(\w+)\?(?:[^#]*&)?page=(\d+)}
      key, page = $1, $2.to_i
      page > 1 ? Response.new("200", { key => [] }.to_json, {}) : dated(key, key.downcase, uri, key == "BankTransactions" ? "DateString" : "Date")
    when %r{/(\w+)\z}
      fixture($1.downcase)
    else
      Response.new("404", "no fixture for #{uri}", {})
    end
  end

  private

  # Xero applies a Date>= where clause server-side; so does the fake.
  def dated(key, name, uri, field)
    items = JSON.parse(fixture(name).body)[key]
    if (m = CGI.unescape(uri.query.to_s).match(/Date>=DateTime\((\d+),(\d+),(\d+)\)/))
      floor = Date.new(m[1].to_i, m[2].to_i, m[3].to_i)
      items = items.select { |i| i[field] && Xero::Client.parse_date(i[field]) >= floor }
    end
    Response.new("200", { key => items }.to_json, {})
  end

  def fixture(name) = Response.new("200", Rails.root.join("test/fixtures/files/xero_api/#{name}.json").read, {})
end

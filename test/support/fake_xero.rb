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
    when %r{/Journals\?offset=(\d+)}
      $1.to_i.zero? ? fixture("journals") : Response.new("200", { "Journals" => [] }.to_json, {})
    when %r{/(\w+)\?page=(\d+)}
      $2.to_i > 1 ? Response.new("200", { $1 => [] }.to_json, {}) : fixture($1.downcase)
    when %r{/(\w+)\z}
      fixture($1.downcase)
    else
      Response.new("404", "no fixture for #{uri}", {})
    end
  end

  private

  def fixture(name) = Response.new("200", Rails.root.join("test/fixtures/files/xero_api/#{name}.json").read, {})
end

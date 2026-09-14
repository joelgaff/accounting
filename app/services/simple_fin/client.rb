require "net/http"

module SimpleFin
  Account     = Struct.new(:id, :name, :currency, :balance, :balance_date, :transactions, keyword_init: true)
  Transaction = Struct.new(:id, :posted_on, :amount, :description, :payee, :memo, :pending, keyword_init: true)
  Response    = Struct.new(:accounts, :errors, keyword_init: true)

  # The SimpleFIN protocol: a setup token is a base64 claim URL, POSTed once
  # for an access URL with basic-auth credentials embedded; GET /accounts
  # under that URL returns accounts and their transactions. Net::HTTP only;
  # the transport is injectable so tests never touch the network.
  class Client
    MAX_RANGE_DAYS = 90
    DEFAULT_TRANSPORT = lambda do |request, uri|
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 60) { |http| http.request(request) }
    end

    def self.claim(setup_token, transport: DEFAULT_TRANSPORT)
      decoded = Base64.decode64(setup_token.to_s.strip)
      uri = URI.parse(decoded) rescue nil
      raise Error, "That doesn't look like a SimpleFIN setup token" unless uri.is_a?(URI::HTTPS)

      request = Net::HTTP::Post.new(uri)
      request["Content-Length"] = "0"
      response = transport.call(request, uri)
      raise Error, "Claim failed (#{response.code}); a setup token can only be claimed once" unless response.is_a?(Net::HTTPSuccess)
      response.body.to_s.strip
    end

    def initialize(access_url, transport: DEFAULT_TRANSPORT)
      @uri       = URI.parse(access_url)
      @transport = transport
      raise Error, "Access URL has no credentials" if @uri.user.blank? || @uri.password.blank?
    end

    def accounts(start_date:, end_date: Date.current, pending: false)
      raise Error, "SimpleFIN allows at most #{MAX_RANGE_DAYS} days per request" if (end_date - start_date).to_i > MAX_RANGE_DAYS

      uri = @uri.dup
      uri.user = uri.password = nil
      uri.path = File.join(uri.path, "accounts")
      query = { "start-date" => start_date.to_time.to_i, "end-date" => (end_date + 1).to_time.to_i }
      query["pending"] = 1 if pending
      uri.query = URI.encode_www_form(query)

      request = Net::HTTP::Get.new(uri)
      request.basic_auth(URI.decode_www_form_component(@uri.user), URI.decode_www_form_component(@uri.password))
      request["Accept"] = "application/json"
      response = @transport.call(request, uri)
      raise Error, "SimpleFIN returned #{response.code}#{response.code == '402' ? ' (subscription lapsed?)' : ''}" unless response.is_a?(Net::HTTPSuccess)

      parse(JSON.parse(response.body))
    rescue JSON::ParserError
      raise Error, "SimpleFIN returned something that isn't JSON"
    end

    private

    def parse(json)
      accounts = Array(json["accounts"]).map do |a|
        Account.new(
          id: a["id"], name: a["name"], currency: a["currency"],
          balance: BigDecimal(a["balance"].to_s.presence || "0"),
          balance_date: a["balance-date"] ? Time.at(a["balance-date"].to_i).utc : nil,
          transactions: Array(a["transactions"]).map do |t|
            Transaction.new(
              id: t["id"], posted_on: Time.at(t["posted"].to_i).utc.to_date,
              amount: BigDecimal(t["amount"].to_s), description: t["description"],
              payee: t["payee"], memo: t["memo"], pending: t["pending"] == true || t["posted"].to_i.zero?
            )
          end
        )
      end
      Response.new(accounts: accounts, errors: Array(json["errors"]))
    end
  end
end

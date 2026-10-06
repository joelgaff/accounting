require "net/http"

module Xero
  # Xero's OAuth 2.0 and Accounting API over Net::HTTP. Tokens live on the
  # XeroConnection and refresh themselves when they expire. The transport is
  # injectable so tests never touch the network, and a pause between calls
  # keeps a full import under Xero's 60-calls-a-minute limit.
  class Client
    AUTHORIZE_URL = "https://login.xero.com/identity/connect/authorize".freeze
    TOKEN_URL     = "https://identity.xero.com/connect/token".freeze
    CONNECTIONS   = "https://api.xero.com/connections".freeze
    API_BASE      = "https://api.xero.com/api.xro/2.0/".freeze
    SCOPES        = %w[openid offline_access accounting.transactions.read accounting.contacts.read
                       accounting.settings.read accounting.journals.read].freeze
    PAGE_SIZE     = 100

    DEFAULT_TRANSPORT = lambda do |request, uri|
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 120) { |http| http.request(request) }
    end

    class << self
      def client_id     = Rails.application.credentials.dig(:xero, :client_id).presence     || ENV["XERO_CLIENT_ID"].presence
      def client_secret = Rails.application.credentials.dig(:xero, :client_secret).presence || ENV["XERO_CLIENT_SECRET"].presence
      def configured?   = client_id.present? && client_secret.present?

      # Xero's identity server wants the scope list space-separated as %20, not
      # the + that form encoding produces.
      def authorize_url(redirect_uri:, state:)
        query = URI.encode_www_form(response_type: "code", client_id: client_id, redirect_uri: redirect_uri, state: state)
        "#{AUTHORIZE_URL}?#{query}&scope=#{SCOPES.join('%20')}"
      end

      # Swap the code from the callback for tokens: { access_token, refresh_token, expires_at }.
      def exchange_code(code, redirect_uri:, transport: DEFAULT_TRANSPORT)
        token_request({ grant_type: "authorization_code", code: code, redirect_uri: redirect_uri }, transport)
      end

      def refresh(refresh_token, transport: DEFAULT_TRANSPORT)
        token_request({ grant_type: "refresh_token", refresh_token: refresh_token }, transport)
      end

      # The Xero organisations this token can see: [{ "tenantId", "tenantName" }].
      def connections(access_token, transport: DEFAULT_TRANSPORT)
        uri = URI.parse(CONNECTIONS)
        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{access_token}"
        request["Accept"] = "application/json"
        response = transport.call(request, uri)
        raise Error, "Xero connections lookup failed (#{response.code})" unless response.is_a?(Net::HTTPSuccess)
        JSON.parse(response.body)
      end

      # Xero's JSON carries dates as "/Date(1552521600000+0000)/" and, on some
      # records, as plain "2019-09-13T00:00:00" strings. Either becomes a Date.
      def parse_date(value)
        return nil if value.blank?
        if (m = value.to_s.match(%r{/Date\((-?\d+)}))
          Time.at(m[1].to_i / 1000).utc.to_date
        else
          Date.parse(value.to_s)
        end
      rescue ArgumentError
        nil
      end

      private

      def token_request(form, transport)
        raise Error, "Xero client id and secret are not configured" unless configured?
        uri = URI.parse(TOKEN_URL)
        request = Net::HTTP::Post.new(uri)
        request.basic_auth(client_id, client_secret)
        request.set_form_data(form)
        response = transport.call(request, uri)
        raise Error, "Xero token request failed (#{response.code}): #{response.body.to_s[0, 200]}" unless response.is_a?(Net::HTTPSuccess)
        json = JSON.parse(response.body)
        { access_token: json.fetch("access_token"), refresh_token: json.fetch("refresh_token"),
          expires_at: Time.current + json.fetch("expires_in").to_i.seconds }
      end
    end

    def initialize(connection, transport: DEFAULT_TRANSPORT, pause: 1.1)
      @connection = connection
      @transport  = transport
      @pause      = pause
    end

    # One GET against the Accounting API; the response's top-level collection.
    def get(path, params = {}, key:)
      refresh! if @connection.token_expired?
      uri = URI.join(API_BASE, path)
      uri.query = URI.encode_www_form(params) if params.any?
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{@connection.access_token}"
      request["xero-tenant-id"] = @connection.tenant_id
      request["Accept"] = "application/json"

      response = @transport.call(request, uri)
      if response.code == "429"
        sleep [ response["Retry-After"].to_i, 65 ].min.clamp(1, 65)
        response = @transport.call(request, uri)
      end
      raise Error, "Xero #{path} failed (#{response.code}): #{response.body.to_s[0, 200]}" unless response.is_a?(Net::HTTPSuccess)
      sleep @pause if @pause.positive?
      Array(JSON.parse(response.body)[key])
    rescue JSON::ParserError
      raise Error, "Xero #{path} returned something that isn't JSON"
    end

    # Page-numbered collections (Invoices, Contacts, Payments): 100 a page until a short page.
    def each_page(path, params = {}, key:)
      return enum_for(:each_page, path, params, key: key) unless block_given?
      page = 1
      loop do
        items = get(path, params.merge(page: page), key: key)
        items.each { |item| yield item }
        break if items.size < PAGE_SIZE
        page += 1
      end
    end

    # Journals page by offset: each call returns the 100 journals after that journal number.
    def each_journal(from_number: 0)
      return enum_for(:each_journal, from_number: from_number) unless block_given?
      offset = from_number
      loop do
        items = get("Journals", { offset: offset }, key: "Journals")
        items.each { |item| yield item }
        break if items.size < PAGE_SIZE
        offset = items.last["JournalNumber"]
      end
    end

    private

    def refresh!
      tokens = self.class.refresh(@connection.refresh_token, transport: @transport)
      @connection.update!(access_token: tokens[:access_token], refresh_token: tokens[:refresh_token], token_expires_at: tokens[:expires_at])
    end
  end
end

# Which way people sign in. Launchpad mode when the credentials carry a
# `launchpad` block (the hub's URL, issuer and cookie domain); local mode,
# the built-in magic-code login, otherwise. AUTH_MODE=local|launchpad in
# the environment overrides, for development against no hub.
module Auth
  MODES = %w[launchpad local].freeze

  class << self
    def mode
      forced = ENV["AUTH_MODE"].presence
      return forced if MODES.include?(forced)
      launchpad_settings.present? ? "launchpad" : "local"
    end

    def launchpad? = mode == "launchpad"
    def local?     = mode == "local"

    # The hub, with the environment file able to point at a local copy.
    def launchpad_base_url
      Rails.application.config.x.launchpad_base_url.presence || launchpad_settings&.dig(:base_url)
    end

    def launchpad_issuer        = launchpad_settings&.dig(:issuer)
    def launchpad_cookie_domain = Rails.application.config.x.jwt_cookie_domain.presence || launchpad_settings&.dig(:cookie_domain)

    # Where this app is served, for allowed hosts and links in email.
    def app_host = Rails.application.credentials.dig(:app, :host).presence || ENV["APP_HOST"].presence

    private

    def launchpad_settings = Rails.application.credentials.launchpad
  end
end

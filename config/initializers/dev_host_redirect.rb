# Development only. The Launchpad SSO cookie is scoped to .lvh.me, so a
# localhost URL can never be signed in and would loop through the hub forever.
# Bounce any localhost request to the same path on accounting.lvh.me.
if Rails.env.development?
  class DevHostRedirect
    LOCAL_HOSTS = %w[localhost 127.0.0.1 ::1 [::1]].freeze

    def initialize(app) = @app = app

    def call(env)
      request = Rack::Request.new(env)
      return @app.call(env) unless LOCAL_HOSTS.include?(request.host)

      target = "#{request.scheme}://accounting.lvh.me:#{request.port}#{request.fullpath}"
      [ 302, { "location" => target, "content-type" => "text/plain" }, [ "Redirecting to #{target}\n" ] ]
    end
  end

  Rails.application.config.middleware.insert_before 0, DevHostRedirect
end

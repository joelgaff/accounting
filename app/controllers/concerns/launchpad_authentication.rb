module LaunchpadAuthentication
  extend ActiveSupport::Concern

  # This app's key in the Launchpad app registry; the JWT must list it in `apps`.
  APP_KEY = "accounting".freeze

  included do
    before_action :require_launchpad_authentication
    helper_method :current_user, :logged_in?
  end

  private

  def require_launchpad_authentication
    claims = Ee::Jwt.decode(cookies[Ee::Jwt::COOKIE_NAME])
    return redirect_to_launchpad if claims.nil?
    return render_no_access unless claims["apps"].to_a.include?(APP_KEY)

    Current.user = sync_user(claims)
  end

  # Sync on the STABLE public_id (claims["sub"]), never email — email can change
  # at Launchpad without spawning a duplicate local record.
  def sync_user(claims)
    User.find_or_initialize_by(launchpad_public_id: claims["sub"]).tap do |user|
      user.email_address = claims["email"]
      user.name          = claims["name"]
      user.organization ||= Current.organization || Organization.first
      user.save! if user.changed?
    end
  end

  # Silent-refresh entry point: /token mints a fresh JWT if the hub session is
  # live, otherwise the hub bounces to its login form (return_to preserved).
  def redirect_to_launchpad
    return_to = CGI.escape(request.original_url)
    redirect_to "#{launchpad_base_url}/token?return_to=#{return_to}", allow_other_host: true
  end

  def render_no_access
    render "shared/no_access", status: :forbidden
  end

  def launchpad_base_url = Rails.application.config.x.launchpad_base_url

  def current_user = Current.user
  def logged_in?   = Current.user.present?
end

# One "require authentication" step for every controller, delegating to the
# active sign-in strategy (Auth.mode): the Launchpad hub's JWT cookie, or the
# built-in magic-code session. Both set Current.user.
module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :current_user, :logged_in?
  end

  private

  def require_authentication
    Auth.launchpad? ? require_launchpad_authentication : require_local_login
  end

  # ── Local mode: a user id in the Rails cookie session (rails-now's shape) ──

  def require_local_login
    Current.user ||= User.local.find_by(id: session[:user_id])
    return if Current.user
    return redirect_to new_setup_path if User.local.none?
    redirect_to new_session_path, alert: "Please sign in."
  end

  def sign_in(user)
    reset_session
    session[:user_id] = user.id
    Current.user = user
  end

  def sign_out
    reset_session
    Current.user = nil
  end

  def current_user = Current.user
  def logged_in?   = Current.user.present?
end

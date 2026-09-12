class ApplicationController < ActionController::Base
  # Adds before_action :require_launchpad_authentication.
  include LaunchpadAuthentication

  # Must resolve the tenant BEFORE the SSO user is synced (a first-time user is
  # attached to it), so prepend it ahead of the concern's auth filter.
  before_action :set_organization, prepend: true

  private

  # SINGLE-TENANT today: the one tenant.
  def set_organization
    Current.organization = Organization.first
  end
end

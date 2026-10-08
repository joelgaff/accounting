class ApplicationController < ActionController::Base
  # Adds before_action :require_authentication, which picks the strategy.
  include LaunchpadAuthentication
  include Authentication

  # Must resolve the tenant BEFORE the SSO user is synced (a first-time user is
  # attached to it), so prepend it ahead of the concern's auth filter.
  before_action :set_organization, prepend: true

  # Pages a person reaches before they have signed in.
  def self.allow_unauthenticated(**options)
    skip_before_action :require_authentication, **options
  end

  private

  # SINGLE-TENANT today: the one tenant, self-healing on a fresh database so a
  # first SSO sign-in has an organization to attach the synced user to (a fresh
  # deploy otherwise 422s when sync_user hits the required organization).
  def set_organization
    Current.organization = Organization.first || Organization.create!(name: "Default")
  end

  # Invoices and bills post to one receivable or payable account, chosen once
  # in Settings; a form never asks. Without it there is nothing to post to.
  def require_control_account(attr, label, noun)
    return if Current.organization.settings.public_send(attr).present?
    redirect_to settings_path, alert: "Pick your #{label} account under Control accounts before creating #{noun}."
  end
end

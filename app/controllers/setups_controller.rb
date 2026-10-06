# First run in local mode: with no users yet, every path lands here. The
# organisation and the first user are created together once the email is
# proven by a code. The page stops existing the moment a user does.
class SetupsController < ApplicationController
  allow_unauthenticated
  before_action :refuse_once_set_up

  def new
    @organization = Organization.first || Organization.new
  end

  def create
    email = User.normalize_value_for(:email_address, params[:email])
    name  = params[:name].to_s.strip
    @organization = Organization.first || Organization.new
    @organization.name = params[:organization_name].to_s.strip

    user = nil
    ActiveRecord::Base.transaction do
      @organization.save!
      user = @organization.users.create!(email_address: email, name: name.presence || email.split("@").first)
    end
    code = user.issue_login_code!
    LoginMailer.code(user, code).deliver_later
    redirect_to verify_session_path(token: Rails.application.message_verifier(:login).generate(email, expires_in: 15.minutes)),
                notice: "Check #{email} for your first sign-in code."
  rescue ActiveRecord::RecordInvalid => e
    flash.now[:alert] = e.record.errors.full_messages.to_sentence
    render :new, status: :unprocessable_entity
  end

  private

  def refuse_once_set_up
    redirect_to new_session_path if Auth.launchpad? || User.local.exists?
  end
end

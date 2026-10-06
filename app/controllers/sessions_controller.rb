# Built-in sign-in: email → six-digit code by email → code entry → session.
# In Launchpad mode these pages hand over to the hub.
class SessionsController < ApplicationController
  allow_unauthenticated only: %i[new create verify confirm]
  before_action :hand_over_to_launchpad, if: -> { Auth.launchpad? }

  # Step 1: ask for the email.
  def new; end

  # Step 1 submit: issue and email a code if the address is known. The
  # response is the same either way, so the form never says who has an account.
  def create
    email = User.normalize_value_for(:email_address, params[:email])
    if (user = User.local.find_by(email_address: email))
      begin
        code = user.issue_login_code!
        LoginMailer.code(user, code).deliver_later
      rescue User::TooManyRequests
        # Silently: the page still moves on, and the last code they were sent remains valid.
      end
    end
    redirect_to verify_session_path(token: email_token(email)), notice: "If that address has an account, a 6-digit code is on its way."
  end

  # Step 2: enter the code. A link from the email arrives with it prefilled.
  def verify
    @email = email_from_token or return redirect_to(new_session_path, alert: "That sign-in link has expired. Start again.")
    @code  = params[:code]
  end

  # Step 2 submit: check the code, start the session.
  def confirm
    @email = email_from_token or return redirect_to(new_session_path, alert: "That sign-in link has expired. Start again.")
    user   = User.local.find_by(email_address: @email)
    if user&.login_code_valid?(params[:code])
      user.clear_login_code!
      sign_in(user)
      redirect_to root_path, notice: "Signed in."
    else
      flash.now[:alert] = "That code isn't right or has expired."
      render :verify, status: :unprocessable_entity
    end
  end

  def destroy
    sign_out
    redirect_to new_session_path, notice: "Signed out."
  end

  private

  TOKEN_TTL = 15.minutes

  # The verify page is addressed by a signed, short-lived token for the email,
  # so no user id is exposed and a guessed URL leads nowhere.
  def email_token(email)   = Rails.application.message_verifier(:login).generate(email, expires_in: TOKEN_TTL)
  def email_from_token     = Rails.application.message_verifier(:login).verified(params[:token].to_s)

  def hand_over_to_launchpad
    action_name == "destroy" ? redirect_to("#{Auth.launchpad_base_url}/session", allow_other_host: true) : redirect_to_launchpad
  end
end

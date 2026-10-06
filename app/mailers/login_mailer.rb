class LoginMailer < ApplicationMailer
  # The six-digit code, with a link that arrives on the code page with it filled in.
  def code(user, code)
    @user, @code = user, code
    @link = verify_session_url(token: Rails.application.message_verifier(:login).generate(user.email_address, expires_in: 15.minutes), code: code)
    mail to: user.email_address, subject: "Your login code: #{code}"
  end

  # A new person added under Settings → People.
  def welcome(user, added_by:)
    @user, @added_by = user, added_by
    @link = new_session_url
    mail to: user.email_address, subject: "You've been added to #{Rails.application.config.x.app_name}"
  end
end

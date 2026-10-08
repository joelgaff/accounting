class LoginMailer < ApplicationMailer
  # The six-digit code, with a link that arrives on the code page with it filled in.
  # `to:` sends it somewhere other than the user's current address, for an
  # email change that must be proven at the new one.
  def code(user, code, to: nil)
    @user, @code = user, code
    @link = verify_session_url(token: Rails.application.message_verifier(:login).generate(user.email_address, expires_in: 15.minutes), code: code)
    mail to: to || user.email_address, subject: "Your login code: #{code}", **sender_for(user.organization)
  end

  # Tells the old address its sign-in email moved, in case it wasn't them.
  def email_changed(user, old_address:)
    @user, @old_address = user, old_address
    mail to: old_address, subject: "Your #{Rails.application.config.x.app_name} sign-in email changed", **sender_for(user.organization)
  end

  # A new person added under Settings → People.
  def welcome(user, added_by:)
    @user, @added_by = user, added_by
    @link = new_session_url
    mail to: user.email_address, subject: "You've been added to #{Rails.application.config.x.app_name}", **sender_for(user.organization)
  end
end

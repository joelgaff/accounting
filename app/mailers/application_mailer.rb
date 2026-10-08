class ApplicationMailer < ActionMailer::Base
  layout "mailer"

  # The sending address lives with the SMTP credentials (smtp.from); MAIL_FROM
  # remains as an override, and the example address only ever shows in dev.
  # Only an operator can change it, since the provider must have verified it.
  def self.sending_address
    Rails.application.credentials.dig(:smtp, :from) || ENV.fetch("MAIL_FROM", "no-reply@example.com")
  end

  default from: -> { email_address_with_name(ApplicationMailer.sending_address, Rails.application.config.x.app_name) }

  private

  # From and reply-to for mail sent on an organisation's behalf: its name on
  # the operator's address, replies wherever Settings says.
  def sender_for(organization)
    settings = organization.settings
    { from: email_address_with_name(ApplicationMailer.sending_address, settings.email_sender_name),
      reply_to: settings.email_reply_to }.compact
  end
end

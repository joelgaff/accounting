class ApplicationMailer < ActionMailer::Base
  # The sending address lives with the SMTP credentials (smtp.from); MAIL_FROM
  # remains as an override, and the example address only ever shows in dev.
  default from: -> { email_address_with_name(Rails.application.credentials.dig(:smtp, :from) || ENV.fetch("MAIL_FROM", "no-reply@example.com"), Rails.application.config.x.app_name) }
  layout "mailer"
end

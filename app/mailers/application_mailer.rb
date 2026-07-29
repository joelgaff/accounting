class ApplicationMailer < ActionMailer::Base
  # Override with MAIL_FROM env var (Hatchbox sets it in prod).
  default from: ENV.fetch("MAIL_FROM", "no-reply@example.com")
  layout "mailer"
end

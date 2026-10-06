# Links in email need the app's host. Say so loudly in production rather
# than mailing "localhost" links.
Rails.application.config.after_initialize do
  if Rails.env.production? && Rails.application.credentials.dig(:app, :host).blank? && ENV["APP_HOST"].blank?
    Rails.logger.warn "[Partita Doppia] app.host is not set in credentials (or APP_HOST); links in email will point at localhost."
  end
end

# The built-in sign-in keeps the user id in the cookie session: thirty days,
# refreshed on use, never readable by scripts, not sent cross-site.
Rails.application.config.session_store :cookie_store, key: "_partita_doppia_session", expire_after: 30.days, same_site: :lax, httponly: true

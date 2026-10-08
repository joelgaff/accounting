require "test_helper"

# Browser tests. Headless Chromium; a phone-sized window is one line away.
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  PHONE   = [ 390, 844 ].freeze    # iPhone 14/15 CSS pixels
  DESKTOP = [ 1440, 900 ].freeze

  driven_by :selenium, using: :headless_chrome, screen_size: DESKTOP do |options|
    binary = ENV["CHROME_BIN"].presence || %w[/usr/bin/chromium /usr/bin/chromium-browser /usr/bin/google-chrome].find { |b| File.exist?(b) }
    options.binary = binary if binary
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--force-device-scale-factor=1")
  end

  def resize_to(width, height) = page.driver.browser.manage.window.resize_to(width, height)
  def on_phone   = resize_to(*PHONE)
  def on_desktop = resize_to(*DESKTOP)

  # Same SSO cookie the integration tests use, set in the real browser.
  def sign_in_as_launchpad_user(org, email: "joel@example.com", name: "Joel")
    Organization.where.not(id: org.id).destroy_all
    payload = { sub: "u-#{org.id}", email: email, name: name, apps: [ "partita_doppia" ],
                iat: Time.current.to_i, exp: 1.hour.from_now.to_i, iss: Ee::Jwt.issuer }
    token = ::JWT.encode(payload, Rails.application.credentials.ee_jwt_secret, "HS256")
    visit "/up"                                     # any page on the app's host, so the cookie has a domain
    page.driver.browser.manage.add_cookie(name: Ee::Jwt::COOKIE_NAME.to_s, value: token, path: "/")
  end

  # SHOTS=1 saves a PNG of the current page under tmp/screenshots for a look.
  def shoot(label)
    return unless ENV["SHOTS"].present?
    FileUtils.mkdir_p(Rails.root.join("tmp/screenshots"))
    page.save_screenshot(Rails.root.join("tmp/screenshots", "#{label.parameterize}.png").to_s)
  end

  # The page fits the viewport: no sideways scroll on the document.
  def assert_fits_viewport(label = page.current_path)
    scroll_width, client_width = page.evaluate_script("[document.documentElement.scrollWidth, document.documentElement.clientWidth]")
    assert scroll_width <= client_width, "#{label} scrolls sideways: #{scroll_width}px wide in a #{client_width}px viewport"
  end
end

require "test_helper"

class LaunchpadAuthenticationTest < ActionDispatch::IntegrationTest
  setup do
    @org = organizations(:one)
    # Single-tenant: set_organization resolves Organization.first.
    Organization.where.not(id: @org.id).destroy_all
  end

  # Mint a suite JWT exactly as Launchpad would (same secret, claims, issuer).
  def ee_jwt(sub: SecureRandom.uuid, email: "joel@example.com", name: "Joel", apps: [ "accounting" ])
    payload = { sub:, email:, name:, apps:,
                iat: Time.current.to_i, exp: 24.hours.from_now.to_i,
                iss: Ee::Jwt::ISSUER }
    ::JWT.encode(payload, Rails.application.credentials.ee_jwt_secret, "HS256")
  end

  def set_jwt(token) = cookies[Ee::Jwt::COOKIE_NAME.to_s] = token

  test "no JWT bounces to the Launchpad hub token endpoint with return_to" do
    get "/"
    assert_response :redirect
    assert_match %r{\Ahttps://launchpad\.example\.com/token\?return_to=}, response.location
    assert_includes response.location, CGI.escape("http://www.example.com/")
  end

  test "a valid JWT that grants accounting serves the page and syncs the user" do
    token = ee_jwt(sub: "abc-123", email: "joel@example.com", name: "Joel Gaff")
    set_jwt(token)

    assert_difference -> { User.count }, 1 do
      get "/"
    end
    assert_response :success

    user = User.find_by!(launchpad_public_id: "abc-123")
    assert_equal "joel@example.com", user.email_address
    assert_equal "Joel Gaff",        user.name
    assert_equal @org,               user.organization
  end

  test "re-visiting with the same JWT does not create a second user" do
    set_jwt(ee_jwt(sub: "abc-123"))
    get "/"
    assert_no_difference -> { User.count } do
      set_jwt(ee_jwt(sub: "abc-123"))
      get "/invoices"
    end
    assert_response :success
  end

  test "a JWT without the accounting app is denied access" do
    set_jwt(ee_jwt(sub: "no-access", apps: %w[vendors travel]))
    get "/"
    assert_response :forbidden
    assert_match(/don't have access/i, response.body)
  end

  test "a tampered/foreign JWT is rejected and bounces to the hub" do
    bad = ::JWT.encode({ sub: "x", apps: [ "accounting" ], iss: Ee::Jwt::ISSUER,
                         exp: 1.hour.from_now.to_i }, "wrong-secret", "HS256")
    set_jwt(bad)
    get "/"
    assert_response :redirect
    assert_match %r{/token\?return_to=}, response.location
  end

  test "an email change at the hub updates the same user, not a duplicate" do
    set_jwt(ee_jwt(sub: "abc-123", email: "old@example.com"))
    get "/"
    set_jwt(ee_jwt(sub: "abc-123", email: "new@example.com"))
    assert_no_difference -> { User.count } do
      get "/"
    end
    assert_equal "new@example.com", User.find_by(launchpad_public_id: "abc-123").email_address
  end
end

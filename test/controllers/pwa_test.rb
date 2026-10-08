require "test_helper"

# Installed to a home screen, the window follows the person's theme.
class PwaTest < ActionDispatch::IntegrationTest
  setup do
    @org = organizations(:one)
    sign_in_as_launchpad_user(@org)
  end

  test "the manifest paints the window in the theme it is asked for" do
    get pwa_manifest_path(format: :json, theme: "light")
    assert_equal "#eef2f7", response.parsed_body["theme_color"]
    assert_equal "#eef2f7", response.parsed_body["background_color"]
    assert_equal "standalone", response.parsed_body["display"]
    assert_equal "/", response.parsed_body["id"]

    get pwa_manifest_path(format: :json)
    assert_equal "#060a12", response.parsed_body["theme_color"]
  end

  test "the page links the manifest for its theme and sets the status bar to match" do
    get root_path
    assert_select "link[rel=manifest][href=?]", pwa_manifest_path(format: :json, theme: "dark")
    assert_select "meta[name=apple-mobile-web-app-status-bar-style][content=black-translucent]"

    User.find_by!(email_address: "joel@example.com").update!(theme: "light")
    get root_path
    assert_select "link[rel=manifest][href=?]", pwa_manifest_path(format: :json, theme: "light")
    assert_select "meta[name=apple-mobile-web-app-status-bar-style][content=default]"
  end
end

require "test_helper"

class EmailSenderSettingsTest < ActionDispatch::IntegrationTest
  setup do
    @org = organizations(:one)
    sign_in_as_launchpad_user(@org)
  end

  test "the Organisation panel sets the sender name and reply-to, and refuses a bad address" do
    get settings_path
    assert_select "input[name='organization_settings[email_from_name]']"
    assert_select "input[name='organization_settings[email_reply_to]']"
    assert_match(/#{Regexp.escape(ApplicationMailer.sending_address)}/, response.body, "the page says which address mail leaves from")

    patch emailing_settings_path, params: { organization_settings: { email_from_name: "EE Timing Billing", email_reply_to: "joel@enduranceevolution.example" } }
    assert_redirected_to settings_path
    settings = @org.settings.reload
    assert_equal "EE Timing Billing", settings.email_from_name
    assert_equal "joel@enduranceevolution.example", settings.email_reply_to

    patch emailing_settings_path, params: { organization_settings: { email_from_name: "", email_reply_to: "not an address" } }
    assert_redirected_to settings_path
    assert_match(/reply/i, flash[:alert])
    assert_equal "joel@enduranceevolution.example", settings.reload.email_reply_to

    patch emailing_settings_path, params: { organization_settings: { email_from_name: "", email_reply_to: "" } }
    assert_nil settings.reload.email_from_name
    assert_nil settings.email_reply_to
  end
end

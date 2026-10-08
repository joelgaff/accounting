require "test_helper"

class InvoiceNumberingSettingsTest < ActionDispatch::IntegrationTest
  setup do
    @org = organizations(:one)
    sign_in_as_launchpad_user(@org)
    @ar    = Plutus::Asset.create!(tenant: @org, name: "AR", code: "1200")
    @sales = Plutus::Revenue.create!(tenant: @org, name: "Sales", code: "4100")
  end

  test "the Books panel shows the numbering and saves a new prefix and next number" do
    get settings_path
    assert_select "input[name='organization_settings[invoice_prefix]'][value='INV-']"
    assert_select "input[name='organization_settings[invoice_next_number]']"

    patch invoicing_settings_path, params: { organization_settings: { invoice_prefix: "INV-", invoice_next_number: "2380" } }
    assert_redirected_to settings_path
    assert_equal 2380, @org.settings.reload.invoice_next_number

    get new_invoice_path
    assert_select "input[name='document[documentable_attributes][number]'][value='INV-2380']"
  end

  test "a bad next number is refused with a message" do
    patch invoicing_settings_path, params: { organization_settings: { invoice_prefix: "INV-", invoice_next_number: "0" } }
    assert_redirected_to settings_path
    assert_match(/next number/i, flash[:alert])
    assert_nil OrganizationSettings.find_by(organization: @org)&.invoice_next_number
  end
end

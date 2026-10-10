require "test_helper"

# Settings → Books names the revenue account a picked-up billable expense
# defaults to on an invoice. Blank means the expense line's own account.
class BillableIncomeSettingsTest < ActionDispatch::IntegrationTest
  setup do
    @org = organizations(:one)
    sign_in_as_launchpad_user(@org)
    @billable = Plutus::Revenue.create!(tenant: @org, name: "Billable Expense Income", code: "4721")
    @sales    = Plutus::Revenue.create!(tenant: @org, name: "Sales", code: "4100")
    @travel   = Plutus::Expense.create!(tenant: @org, name: "Travel", code: "6812")
  end

  test "the Books panel offers the revenue accounts and saves the choice" do
    get settings_path
    assert_select "select[name='organization_settings[billable_income_account_id]']" do
      assert_select "option[value=?]", @billable.id.to_s, text: /Billable Expense Income/
      assert_select "option[value=?]", @travel.id.to_s, 0, "expense accounts are not offered"
    end

    patch billing_settings_path, params: { organization_settings: { billable_income_account_id: @billable.id } }
    assert_redirected_to settings_path
    assert_match(/Billable Expense Income/, flash[:notice])
    assert_equal @billable, @org.settings.reload.billable_income_account

    patch billing_settings_path, params: { organization_settings: { billable_income_account_id: "" } }
    assert_nil @org.settings.reload.billable_income_account
    assert_match(/own account/i, flash[:notice])
  end

  test "an account that is not revenue, or not ours, is refused" do
    patch billing_settings_path, params: { organization_settings: { billable_income_account_id: @travel.id } }
    assert_redirected_to settings_path
    assert_match(/not saved/i, flash[:alert])
    assert_nil OrganizationSettings.find_by(organization: @org)&.billable_income_account

    other = Plutus::Revenue.create!(tenant: Organization.create!(name: "Other"), name: "Theirs")
    patch billing_settings_path, params: { organization_settings: { billable_income_account_id: other.id } }
    assert_match(/not saved/i, flash[:alert])
    assert_nil OrganizationSettings.find_by(organization: @org)&.billable_income_account
  end
end

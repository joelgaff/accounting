require "test_helper"

class OrganizationSettingsTest < ActiveSupport::TestCase
  setup { @org = organizations(:one) }

  test "Organization#settings auto-builds when missing" do
    assert_nil OrganizationSettings.find_by(organization: @org)
    s = @org.settings
    assert_instance_of OrganizationSettings, s
    assert s.new_record?
  end

  test "wires KPI account slots" do
    bank = Plutus::Asset.create!(tenant: @org, name: "Bank")
    ar   = Plutus::Asset.create!(tenant: @org, name: "AR")
    ap   = Plutus::Liability.create!(tenant: @org, name: "AP")

    s = @org.settings
    s.update!(bank_account: bank, receivable_account: ar, payable_account: ap)

    @org.reload
    assert_equal bank, @org.settings.bank_account
    assert_equal ar,   @org.settings.receivable_account
    assert_equal ap,   @org.settings.payable_account
  end
end

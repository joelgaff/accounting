require "test_helper"

# The number a contact knows you by: your vendor or customer number with them.
class ContactAccountNumberTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
  end

  test "a contact carries an account number, and Xero's AccountNumber lands in it" do
    ironman = @org.contacts.create!(name: "Ironman", kind: "customer", account_number: "EE-7788")
    assert_equal "EE-7788", ironman.reload.account_number
    assert_not Contact.column_names.include?("company_number"), "the old name is gone"

    ContactsImportService.new(file_fixture("xero/contacts.csv").read, organization: @org, default_kind: "customer").call
    assert_equal "ACME-01", @org.contacts.find_by!(name: "Acme Widgets").account_number
  end
end

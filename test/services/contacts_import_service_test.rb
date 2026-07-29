require "test_helper"

class ContactsImportServiceTest < ActiveSupport::TestCase
  setup { @org = organizations(:one) }

  def call(csv, **opts)
    ContactsImportService.new(csv, organization: @org, **opts).call
  end

  test "imports a Xero Contacts CSV fixture end-to-end" do
    csv = file_fixture("xero/contacts.csv").read
    result = call(csv, default_kind: "customer")

    assert_equal 2, result.created
    assert_equal 1, result.skipped
    assert_equal 1, result.errors.size

    acme = @org.contacts.find_by(name: "Acme Widgets")
    assert_equal "billing@acme.example", acme.email
    assert_equal "Jane",   acme.first_name
    assert_equal "12345",  acme.postal_code
    assert_equal "Springfield", acme.city
    assert_equal "customer", acme.kind
  end

  test "re-import updates existing by name and keeps kind" do
    @org.contacts.create!(name: "Acme Widgets", kind: "vendor", email: "old@x.com")
    csv = file_fixture("xero/contacts.csv").read
    result = call(csv, default_kind: "customer")

    assert_equal 1, result.created
    assert_equal 1, result.updated
    acme = @org.contacts.find_by(name: "Acme Widgets")
    assert_equal "vendor", acme.kind  # existing kind preserved
    assert_equal "billing@acme.example", acme.email
  end

  test "requires a ContactName column" do
    result = call("Foo,Bar\n1,2\n")
    assert_match(/ContactName/, result.errors.first)
  end
end

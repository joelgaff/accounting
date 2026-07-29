require "test_helper"

class ContactTest < ActiveSupport::TestCase
  setup { @org = organizations(:one) }

  test "requires name and valid kind" do
    c = @org.contacts.build
    assert_not c.valid?
    c.name = "Acme"
    c.kind = "invalid"
    assert_not c.valid?
    c.kind = "customer"
    assert c.valid?
  end

  test "customer/vendor scopes include both-kind" do
    a = @org.contacts.create!(name: "A", kind: "customer")
    b = @org.contacts.create!(name: "B", kind: "vendor")
    c = @org.contacts.create!(name: "C", kind: "both")

    assert_equal [a, c].sort, @org.contacts.customers.to_a.sort_by(&:id)
    assert_equal [b, c].sort, @org.contacts.vendors.to_a.sort_by(&:id)
  end

  test "invoice with contact syncs client_name" do
    ar    = Plutus::Asset.create!(tenant: @org, name: "AR")
    sales = Plutus::Revenue.create!(tenant: @org, name: "Sales")
    Current.organization = @org
    contact = @org.contacts.create!(name: "Big Client", kind: "customer")

    inv = @org.invoices.create!(
      contact: contact, amount: 100, due_date: Date.current + 10,
      receivable_account: ar, revenue_account: sales
    )
    assert_equal "Big Client", inv.client_name
    assert_equal "Big Client", inv.customer_display
  end
end

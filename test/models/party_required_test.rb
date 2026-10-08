require "test_helper"

# Every expense and deposit names who it was with: a contact, not a string.
class PartyRequiredTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @bank    = create_bank_account(@org, name: "Checking")
    @hosting = Plutus::Expense.create!(tenant: @org, name: "Hosting")
    @sales   = Plutus::Revenue.create!(tenant: @org, name: "Sales")
  end

  def expense(**attrs)
    @org.documents.build({ date: Date.current, documentable: Expense.new(bank_account: @bank),
                           line_items_attributes: [ { description: "x", quantity: 1, unit_amount: 5, account_id: @hosting.id } ] }.merge(attrs))
  end

  def deposit(**attrs)
    @org.documents.build({ date: Date.current, documentable: Deposit.new(bank_account: @bank),
                           line_items_attributes: [ { description: "x", quantity: 1, unit_amount: 5, account_id: @sales.id } ] }.merge(attrs))
  end

  test "an expense or deposit entered here needs a contact" do
    assert_not expense.valid?
    assert_match(/who this was with/i, expense.tap(&:valid?).errors[:contact].join)
    assert_not deposit.valid?
    zoom = @org.contacts.create!(name: "Zoom", kind: "vendor")
    assert expense(contact: zoom).valid?
    assert deposit(contact: zoom).valid?
  end

  test "a name typed on a form becomes the contact, found or made, with the kind the document implies" do
    doc = expense(contact_name: "Blue Pixel Hosting")
    assert doc.save
    assert_equal "Blue Pixel Hosting", doc.contact.name
    assert_equal "vendor", doc.contact.kind
    assert_equal "Blue Pixel Hosting", doc.expense.vendor

    dep = deposit(contact_name: "Summit Races")
    assert dep.save
    assert_equal "customer", dep.contact.kind

    again = expense(contact_name: "blue pixel hosting")
    assert again.save
    assert_equal doc.contact, again.contact, "found by name, case aside"
  end

  test "what Xero imported is not held to it" do
    imported = expense(source: "xero_import"); imported.expense.vendor = "(Xero)"
    assert imported.valid?
    assert deposit(source: "xero_import").valid?
  end
end

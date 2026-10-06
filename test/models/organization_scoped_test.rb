require "test_helper"

class OrganizationScopedTest < ActiveSupport::TestCase
  setup do
    @org   = organizations(:one)
    @other = organizations(:two)
    Current.organization = @org
    @ar = Plutus::Asset.create!(tenant: @org, name: "AR");  @sales = Plutus::Revenue.create!(tenant: @org, name: "Sales")
    @foreign_revenue = Plutus::Revenue.create!(tenant: @other, name: "Theirs")
    @foreign_contact = @other.contacts.create!(name: "Not ours", kind: "customer")
    @foreign_bank    = create_bank_account(@other, name: "Their bank")
  end

  test "a line, a document and a payment refuse references from another organisation" do
    inv = @org.documents.build(date: Date.current, contact: @foreign_contact, documentable: Invoice.new(client_name: "x", due_date: Date.current, receivable_account: @ar))
    inv.line_items.build(description: "x", quantity: 1, unit_amount: 1, account: @foreign_revenue)
    assert_not inv.save
    assert_match(/Contact must belong/, inv.errors.full_messages.join)
    assert_match(/account must belong/i, inv.errors.full_messages.join)

    ok = create_invoice(@org, client_name: "A", amount: 10, receivable: @ar, revenue: @sales)
    payment = ok.payments.build(organization: @org, amount: 5, paid_on: Date.current, bank_account: @foreign_bank)
    assert_not payment.valid?
    assert_match(/Bank account must belong/, payment.errors.full_messages.join)

    @org.settings.bank_account = @foreign_bank
    assert_not @org.settings.valid?
  end
end

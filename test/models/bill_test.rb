require "test_helper"

class BillTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @hosting = Plutus::Expense.create!(tenant: @org,   name: "Hosting")
    @ap      = Plutus::Liability.create!(tenant: @org, name: "Accounts Payable")
  end

  test "a bill accrues to the payable account: DR expense / CR AP" do
    create_bill(@org, vendor: "AWS", amount: 45, category: @hosting, payable: @ap)
    assert_equal BigDecimal("45"), @hosting.balance
    assert_equal BigDecimal("45"), @ap.balance
  end

  test "requires a vendor and a liability payable account" do
    doc = @org.documents.build(date: Date.current, documentable: Bill.new(payable_account: @ap),
                               line_items_attributes: [ { description: "x", quantity: 1, unit_amount: 1, account_id: @hosting.id } ])
    assert_not doc.valid?
    assert doc.errors.full_messages.any? { |m| m =~ /vendor/i }
    assert_raises(ActiveRecord::AssociationTypeMismatch) { Bill.new(payable_account: @hosting) }
  end
end

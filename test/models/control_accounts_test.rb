require "test_helper"

# The receivable and payable accounts are set once in Settings. They cannot go
# blank while documents depend on them, and a draft takes the current one when
# it is approved, so Settings is the truth for anything not yet posted.
class ControlAccountRulesTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @ar    = Plutus::Asset.create!(tenant: @org, name: "Accounts Receivable")
    @ar2   = Plutus::Asset.create!(tenant: @org, name: "Receivables, new")
    @ap    = Plutus::Liability.create!(tenant: @org, name: "Accounts Payable")
    @ap2   = Plutus::Liability.create!(tenant: @org, name: "Payables, new")
    @sales = Plutus::Revenue.create!(tenant: @org, name: "Sales")
    @cost  = Plutus::Expense.create!(tenant: @org, name: "Hosting")
    @org.settings.update!(receivable_account: @ar, payable_account: @ap)
  end

  test "a control account can go blank only while nothing uses it" do
    assert @org.settings.update(receivable_account: nil)
    @org.settings.update!(receivable_account: @ar)

    create_invoice(@org, client_name: "A", amount: 10, receivable: @ar, revenue: @sales)
    assert_not @org.settings.update(receivable_account: nil)
    assert_match(/invoices/, @org.settings.errors[:receivable_account].join)
    assert @org.settings.reload.update(receivable_account: @ar2), "changing to another account is allowed"

    create_bill(@org, vendor: "V", amount: 10, category: @cost, payable: @ap)
    assert_not @org.settings.update(payable_account: nil)
    assert_match(/bills/, @org.settings.errors[:payable_account].join)
  end

  test "a draft takes the control account in Settings when approved; approved documents keep theirs" do
    draft    = create_invoice(@org, client_name: "A", amount: 10, receivable: @ar, revenue: @sales, state: "draft")
    approved = create_invoice(@org, client_name: "B", amount: 20, receivable: @ar, revenue: @sales)
    @org.settings.update!(receivable_account: @ar2)

    draft.approve!
    assert_equal @ar2, draft.reload.invoice.receivable_account
    assert_equal BigDecimal("10"), @ar2.balance
    assert_equal @ar,  approved.reload.invoice.receivable_account
    assert_equal BigDecimal("20"), @ar.balance

    bill = create_bill(@org, vendor: "V", amount: 5, category: @cost, payable: @ap, state: "draft")
    @org.settings.update!(payable_account: @ap2)
    bill.approve!
    assert_equal @ap2, bill.reload.bill.payable_account
    assert_equal BigDecimal("5"), @ap2.balance
  end
end

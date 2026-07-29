require "test_helper"

class ExpenseTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @hosting = Plutus::Expense.create!(tenant: @org,   name: "Hosting")
    @bank    = Plutus::Asset.create!(tenant: @org,     name: "Bank")
    @ap      = Plutus::Liability.create!(tenant: @org, name: "Accounts Payable")
    @sales   = Plutus::Revenue.create!(tenant: @org,   name: "Sales")
  end

  test "paid-from-bank expense posts debit expense / credit bank" do
    @org.expenses.create!(
      vendor: "DigitalOcean", amount: 20, incurred_on: Date.current,
      expense_account: @hosting, paid_from_account: @bank
    )
    assert_equal BigDecimal("20"), @hosting.balance
    assert_equal BigDecimal("-20"), @bank.balance
  end

  test "accrued bill posts debit expense / credit AP" do
    @org.expenses.create!(
      vendor: "AWS", amount: 45, incurred_on: Date.current,
      expense_account: @hosting, paid_from_account: @ap
    )
    assert_equal BigDecimal("45"), @ap.balance
  end

  test "rejects a revenue account as paid-from" do
    exp = @org.expenses.build(
      vendor: "X", amount: 1, incurred_on: Date.current,
      expense_account: @hosting, paid_from_account: @sales
    )
    assert_not exp.valid?
    assert_includes exp.errors[:paid_from_account].join, "asset or liability"
  end
end

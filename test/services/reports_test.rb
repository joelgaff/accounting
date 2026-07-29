require "test_helper"

class ReportsTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @bank    = Plutus::Asset.create!(tenant: @org, name: "Bank")
    @ar      = Plutus::Asset.create!(tenant: @org, name: "AR")
    @ap      = Plutus::Liability.create!(tenant: @org, name: "AP")
    @equity  = Plutus::Equity.create!(tenant: @org, name: "Owner Capital")
    @sales   = Plutus::Revenue.create!(tenant: @org, name: "Sales")
    @hosting = Plutus::Expense.create!(tenant: @org, name: "Hosting")

    inv = @org.invoices.create!(client_name: "Acme", amount: 1_000, due_date: Date.current + 30,
                                receivable_account: @ar, revenue_account: @sales)
    @org.expenses.create!(vendor: "AWS", amount: 200, incurred_on: Date.current,
                          expense_account: @hosting, paid_from_account: @bank)
    inv.payments.create!(organization: @org, amount: 400, paid_on: Date.current, bank_account: @bank)
  end

  test "P&L nets revenue minus expenses" do
    r = Reports::ProfitAndLoss.new(organization: @org)
    assert_equal BigDecimal("1000"), r.total_revenue
    assert_equal BigDecimal("200"),  r.total_expenses
    assert_equal BigDecimal("800"),  r.net_income
  end

  test "Balance Sheet balances (A = L + E + Net Income)" do
    r = Reports::BalanceSheet.new(organization: @org)
    # Assets: bank 400-200=200, AR 1000-400=600 → 800
    assert_equal BigDecimal("800"), r.total_assets
    # No liabilities or equity opening balances → 0 + 0 + net_income 800
    assert r.balanced?
  end

  test "Trial Balance debits equal credits" do
    r = Reports::TrialBalance.new(organization: @org)
    assert r.balanced?
    assert_equal r.total_debit, r.total_credit
  end

  test "General Ledger for AR shows invoice + payment with running balance" do
    r = Reports::GeneralLedger.new(organization: @org, account: @ar)
    assert_equal 2, r.lines.size
    # First: invoice → debit 1000, balance 1000
    # Second: payment → credit 400, balance 600
    assert_equal BigDecimal("600"), r.closing_balance
  end
end

require "test_helper"

class Reports::BalanceSheetTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @bank  = Plutus::Asset.create!(tenant: @org, name: "Bank")
    @sales = Plutus::Revenue.create!(tenant: @org, name: "Sales")
    @rent  = Plutus::Expense.create!(tenant: @org, name: "Rent")
    @owner = Plutus::Equity.create!(tenant: @org, name: "Owner capital")

    post Date.new(2024, 3, 1),  debit: @bank, credit: @owner, amount: 1000   # capital, no earnings
    post Date.new(2024, 6, 1),  debit: @bank, credit: @sales, amount: 500
    post Date.new(2024, 7, 1),  debit: @rent, credit: @bank,  amount: 200    # 2024: +300
    post Date.new(2025, 2, 1),  debit: @rent, credit: @bank,  amount: 50     # 2025: -50
    post Date.new(2026, 1, 15), debit: @bank, credit: @sales, amount: 120    # 2026 so far: +120
    post Date.new(2026, 9, 1),  debit: @bank, credit: @sales, amount: 999    # after the as-of date
  end

  test "splits earnings into prior years and the year in progress" do
    r = Reports::BalanceSheet.new(organization: @org, as_of: Date.new(2026, 6, 30))

    assert_equal [ [ 2024, 300 ], [ 2025, -50 ] ], r.prior_year_rows.map { |y| [ y.year, y.amount.to_i ] }
    assert_equal BigDecimal("250"), r.retained_earnings
    assert_equal BigDecimal("120"), r.current_year_earnings
    assert_equal BigDecimal("370"), r.net_income
    assert_equal Date.new(2026, 1, 1), r.current_year_start
    assert r.balanced?
    assert_equal BigDecimal("1370"), r.total_assets
  end

  test "a year with nothing earned is not listed" do
    post Date.new(2023, 5, 1), debit: @bank, credit: @owner, amount: 10
    r = Reports::BalanceSheet.new(organization: @org, as_of: Date.new(2026, 6, 30))
    assert_equal [ 2024, 2025 ], r.prior_year_rows.map(&:year)
  end

  test "an as-of date inside the first year has no retained earnings" do
    r = Reports::BalanceSheet.new(organization: @org, as_of: Date.new(2024, 6, 30))
    assert_empty r.prior_year_rows
    assert_equal BigDecimal("500"), r.current_year_earnings
    assert r.balanced?
  end

  private

  def post(date, debit:, credit:, amount:)
    Ledger.post(description: "t", commercial_document: nil, date: date,
                debits: [ { account: debit, amount: amount } ],
                credits: [ { account: credit, amount: amount } ])
  end
end

require "test_helper"

class TaxRateTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @tax_liability = Plutus::Liability.create!(tenant: @org, name: "Sales Tax Payable")
    @tax_asset     = Plutus::Asset.create!(tenant: @org, name: "Purchase Tax Recoverable")
    @ar     = Plutus::Asset.create!(tenant: @org, name: "AR")
    @sales  = Plutus::Revenue.create!(tenant: @org, name: "Sales")
    @bank   = Plutus::Asset.create!(tenant: @org, name: "Bank")
    @office = Plutus::Expense.create!(tenant: @org, name: "Office Supplies")
  end

  test "invoice with output tax posts DR AR / CR revenue / CR tax liability" do
    rate = @org.tax_rates.create!(name: "GST 10%", rate: 0.10, liability_account: @tax_liability)

    inv = @org.invoices.create!(client_name: "Acme", amount: 100, due_date: Date.current + 30,
                                receivable_account: @ar, revenue_account: @sales, tax_rate: rate)

    assert_equal BigDecimal("100"), inv.subtotal
    assert_equal BigDecimal("10"),  inv.tax_amount
    assert_equal BigDecimal("110"), inv.amount
    assert_equal BigDecimal("110"), @ar.balance
    assert_equal BigDecimal("100"), @sales.balance
    assert_equal BigDecimal("10"),  @tax_liability.balance
  end

  test "expense with recoverable input tax debits asset for tax portion" do
    rate = @org.tax_rates.create!(name: "GST 10%", rate: 0.10,
                                  liability_account: @tax_liability, asset_account: @tax_asset)

    exp = @org.expenses.create!(vendor: "Acme", amount: 200, incurred_on: Date.current,
                                expense_account: @office, paid_from_account: @bank, tax_rate: rate)

    assert_equal BigDecimal("200"), exp.subtotal
    assert_equal BigDecimal("20"),  exp.tax_amount
    assert_equal BigDecimal("220"), exp.amount
    assert_equal BigDecimal("200"), @office.balance
    assert_equal BigDecimal("20"),  @tax_asset.balance
    assert_equal BigDecimal("-220"), @bank.balance
  end

  test "expense without recoverable asset rolls tax into the expense account" do
    rate = @org.tax_rates.create!(name: "US Sales Tax 8.75%", rate: 0.0875, liability_account: @tax_liability)

    exp = @org.expenses.create!(vendor: "Acme", amount: 100, incurred_on: Date.current,
                                expense_account: @office, paid_from_account: @bank, tax_rate: rate)

    assert_equal BigDecimal("8.75"), exp.tax_amount
    assert_equal BigDecimal("108.75"), @office.balance
    assert_equal BigDecimal("0"),      @tax_asset.balance
  end
end

require "test_helper"

class TaxRateTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @tax_liability = Plutus::Liability.create!(tenant: @org, name: "Sales Tax Payable")
    @tax_asset     = Plutus::Asset.create!(tenant: @org, name: "Purchase Tax Recoverable")
    @ar     = Plutus::Asset.create!(tenant: @org, name: "AR")
    @sales  = Plutus::Revenue.create!(tenant: @org, name: "Sales")
    @bank   = create_bank_account(@org, name: "Bank")
    @office = Plutus::Expense.create!(tenant: @org, name: "Office Supplies")
  end

  test "invoice with output tax posts DR AR / CR revenue / CR tax liability" do
    rate = @org.tax_rates.create!(name: "GST 10%", rate: 0.10, liability_account: @tax_liability)

    inv = create_invoice(@org, client_name: "Acme", amount: 100, receivable: @ar, revenue: @sales, tax_rate: rate)

    assert_equal BigDecimal("100"), inv.subtotal
    assert_equal BigDecimal("10"),  inv.tax_amount
    assert_equal BigDecimal("110"), inv.total
    assert_equal BigDecimal("110"), @ar.balance
    assert_equal BigDecimal("100"), @sales.balance
    assert_equal BigDecimal("10"),  @tax_liability.balance
  end

  test "expense with recoverable input tax debits asset for tax portion" do
    rate = @org.tax_rates.create!(name: "GST 10%", rate: 0.10,
                                  liability_account: @tax_liability, asset_account: @tax_asset)

    exp = create_expense(@org, vendor: "Acme", amount: 200, category: @office, bank_account: @bank, tax_rate: rate)

    assert_equal BigDecimal("200"), exp.subtotal
    assert_equal BigDecimal("20"),  exp.tax_amount
    assert_equal BigDecimal("220"), exp.total
    assert_equal BigDecimal("200"), @office.balance
    assert_equal BigDecimal("20"),  @tax_asset.balance
    assert_equal BigDecimal("-220"), @bank.balance
  end

  test "expense without recoverable asset rolls tax into the expense account" do
    rate = @org.tax_rates.create!(name: "US Sales Tax 8.75%", rate: 0.0875, liability_account: @tax_liability)

    exp = create_expense(@org, vendor: "Acme", amount: 100, category: @office, bank_account: @bank, tax_rate: rate)

    assert_equal BigDecimal("8.75"), exp.tax_amount
    assert_equal BigDecimal("108.75"), @office.balance
    assert_equal BigDecimal("0"),      @tax_asset.balance
  end
end

require "test_helper"

class Imports::TaxRatesServiceTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    @liab  = Plutus::Liability.create!(tenant: @org, name: "Sales Tax Payable")
    @asset = Plutus::Asset.create!(tenant: @org, name: "GST Recoverable")
  end

  test "creates rates from percent, fraction and zero, wiring accounts by name" do
    result = Imports::TaxRatesService.new(file_fixture("xero/tax_rates.csv").read, organization: @org).call
    assert_equal 3, result.created, result.errors.inspect
    assert_empty result.errors

    sales = @org.tax_rates.find_by!(name: "Sales Tax 6%")
    assert_equal BigDecimal("0.06"), sales.rate
    assert_equal "OUTPUT", sales.xero_tax_type
    assert_equal @liab, sales.liability_account
    assert sales.sales?

    gst = @org.tax_rates.find_by!(name: "GST on Purchases")
    assert_equal BigDecimal("0.1"), gst.rate
    assert_equal @asset, gst.asset_account
    assert gst.purchase?

    assert @org.tax_rates.find_by!(name: "Tax Exempt").zero?
  end

  test "re-import updates in place and reports bad rows" do
    Imports::TaxRatesService.new(file_fixture("xero/tax_rates.csv").read, organization: @org).call
    csv = "Name,TaxType,Rate\nSales Tax 6%,OUTPUT,7\n,NONE,0\nBad,NONE,abc\n"
    result = Imports::TaxRatesService.new(csv, organization: @org).call

    assert_equal 0, result.created
    assert_equal 1, result.updated
    assert_equal 2, result.skipped
    assert_equal BigDecimal("0.07"), @org.tax_rates.find_by!(name: "Sales Tax 6%").rate
    assert_equal 3, @org.tax_rates.count
  end
end

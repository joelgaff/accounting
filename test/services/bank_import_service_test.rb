require "test_helper"

class BankImportServiceTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @bank    = Plutus::Asset.create!(tenant: @org,  name: "Bank")
    @paired  = Plutus::Equity.create!(tenant: @org, name: "Suspense")
  end

  test "imports rows and skips malformed ones" do
    csv = <<~CSV
      Date,Description,Amount
      2026-07-20,Client payment,250.00
      2026-07-21,Cloudflare,-8.00
      2026-07-22,Bad row,notanumber
    CSV

    result = BankImportService.new(csv, bank_account: @bank, paired_account: @paired).call

    assert_equal 2, result.imported
    assert_equal 1, result.skipped
    assert_equal 1, result.errors.size
    assert_match /row 4/, result.errors.first

    assert_equal BigDecimal("242"), @bank.balance
    assert_equal Plutus::DebitAmount.sum(:amount), Plutus::CreditAmount.sum(:amount)
  end

  test "reports missing required columns" do
    csv = "Foo,Bar\n1,2\n"
    result = BankImportService.new(csv, bank_account: @bank, paired_account: @paired).call
    assert_equal 0, result.imported
    assert_match /Missing required columns/, result.errors.first
  end
end

require "test_helper"

class Imports::XeroBillsServiceTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @ap        = Plutus::Liability.create!(tenant: @org, name: "Accounts Payable")
    @hosting   = Plutus::Expense.create!(tenant: @org, name: "Hosting", code: "400")
    @tax_liab  = Plutus::Liability.create!(tenant: @org, name: "Sales Tax")
    @tax_asset = Plutus::Asset.create!(tenant: @org, name: "GST Recoverable")
    @input     = @org.tax_rates.create!(name: "GST 10%", rate: 0.10, xero_tax_type: "INPUT",
                                        liability_account: @tax_liab, asset_account: @tax_asset)
    @org.settings.update!(payable_account: @ap)
  end

  test "imports Xero bills as expenses accrued to AP" do
    csv = file_fixture("xero/bills.csv").read
    result = Imports::XeroBillsService.new(csv, organization: @org).call

    assert_equal 2, result.created
    assert_equal 0, result.skipped, result.errors.inspect

    # BILL-500: two lines totaling 140 subtotal, +10% input tax = 14, total 154
    bill = @org.expenses.find_by!(xero_invoice_number: "BILL-500")
    assert_equal 2, bill.line_items.count
    assert_equal BigDecimal("140"), bill.subtotal
    assert_equal BigDecimal("14"),  bill.tax_amount
    assert_equal BigDecimal("154"), bill.amount
    assert_equal @ap, bill.paid_from_account

    # Ledger: AP credited 154 (+ BILL-501's 25 = 179 total), Hosting debited subtotals, recoverable asset debited tax
    assert_equal Plutus::DebitAmount.sum(:amount), Plutus::CreditAmount.sum(:amount)
    assert_equal BigDecimal("179"), @ap.balance  # 154 + 25
  end
end

require "test_helper"

class Imports::XeroInvoicesServiceTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @ar        = Plutus::Asset.create!(tenant: @org, name: "Accounts Receivable")
    @sales1    = Plutus::Revenue.create!(tenant: @org, name: "Consulting", code: "200")
    @sales2    = Plutus::Revenue.create!(tenant: @org, name: "Retainer",   code: "210")
    @tax_liab  = Plutus::Liability.create!(tenant: @org, name: "Sales Tax")
    @output    = @org.tax_rates.create!(name: "GST 10%", rate: 0.10, xero_tax_type: "OUTPUT", liability_account: @tax_liab)
    @org.settings.update!(receivable_account: @ar)
  end

  test "imports Xero sales invoices grouped by invoice number" do
    csv = file_fixture("xero/invoices.csv").read
    result = Imports::XeroInvoicesService.new(csv, organization: @org).call

    assert_equal 3, result.created
    assert_equal 0, result.skipped, result.errors.inspect
    assert_empty  result.errors

    # INV-1001 has two lines summing to 10*150 + 20*150 = 4500, +10% tax = 4950
    inv = @org.invoices.find_by!(xero_invoice_number: "INV-1001")
    assert_equal 2, inv.line_items.count
    assert_equal BigDecimal("4500"), inv.subtotal
    assert_equal BigDecimal("450"),  inv.tax_amount
    assert_equal BigDecimal("4950"), inv.amount
    assert_equal "Acme Widgets",     inv.contact.name

    # Trial balance across the whole import
    assert_equal Plutus::DebitAmount.sum(:amount), Plutus::CreditAmount.sum(:amount)
  end

  test "re-import updates in place, no duplicates" do
    csv = file_fixture("xero/invoices.csv").read
    Imports::XeroInvoicesService.new(csv, organization: @org).call

    debits_before = Plutus::DebitAmount.sum(:amount)
    result = Imports::XeroInvoicesService.new(csv, organization: @org).call
    assert_equal 0, result.created
    assert_equal 3, result.updated
    # ledger reset + reposted → same totals
    assert_equal debits_before, Plutus::DebitAmount.sum(:amount)
    assert_equal 3, @org.invoices.count
  end

  test "errors clearly if the CoA is missing the account code" do
    @sales1.destroy
    csv = file_fixture("xero/invoices.csv").read
    result = Imports::XeroInvoicesService.new(csv, organization: @org).call
    # 3 invoices; INV-1001 and INV-1003 reference code 200, so those skip
    assert_operator result.skipped, :>=, 2
    assert(result.errors.any? { |e| e.match?(/"200".*Chart of Accounts/i) })
  end

  test "errors if receivable_account is not configured" do
    @org.settings.update!(receivable_account: nil)
    csv = file_fixture("xero/invoices.csv").read
    result = Imports::XeroInvoicesService.new(csv, organization: @org).call
    assert_match(/receivable/i, result.errors.first)
    assert_equal 0, result.created
  end
end

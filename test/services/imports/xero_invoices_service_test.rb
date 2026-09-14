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
    @bank = create_bank_account(@org, name: "Business Bank Account", code: "090")
    @org.settings.update!(receivable_account: @ar)
  end

  def invoice_by_number(n)
    Invoice.joins(:document).where(documents: { organization_id: @org.id }).find_by!(xero_invoice_number: n).document
  end

  test "imports Xero sales invoices grouped by invoice number" do
    csv = file_fixture("xero/invoices.csv").read
    result = Imports::XeroInvoicesService.new(csv, organization: @org).call

    assert_equal 3, result.created
    assert_equal 0, result.skipped, result.errors.inspect
    assert_empty result.errors

    # INV-1001 has two lines summing to 10*150 + 20*150 = 4500, +10% tax = 4950
    inv = invoice_by_number("INV-1001")
    assert_equal 2, inv.line_items.count
    assert_equal BigDecimal("4500"), inv.subtotal
    assert_equal BigDecimal("450"),  inv.tax_amount
    assert_equal BigDecimal("4950"), inv.total
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
    assert_equal 3, @org.documents.invoices.count
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

  # --- payments carried across from the Xero API pull -------------------------

  test "records a payment when the CSV carries AmountPaid" do
    @org.settings.update!(bank_account: @bank)
    csv = file_fixture("xero/invoices_with_payments.csv").read
    result = Imports::XeroInvoicesService.new(csv, organization: @org).call

    assert_equal 4, result.created

    paid = invoice_by_number("INV-2001")
    assert_equal BigDecimal("1000"), paid.paid_amount
    assert paid.paid?
    assert_equal Date.new(2026, 7, 20), paid.payments.sole.paid_on

    part = invoice_by_number("INV-2002")
    assert_equal BigDecimal("250"), part.paid_amount
    assert_equal "partial", part.status

    unpaid = invoice_by_number("INV-2003")
    assert_equal 0, unpaid.payments.count

    assert_equal Plutus::DebitAmount.sum(:amount), Plutus::CreditAmount.sum(:amount)
  end

  test "re-import replaces its own payment instead of stacking a second one" do
    @org.settings.update!(bank_account: @bank)
    csv = file_fixture("xero/invoices_with_payments.csv").read
    Imports::XeroInvoicesService.new(csv, organization: @org).call
    Imports::XeroInvoicesService.new(csv, organization: @org).call

    paid = invoice_by_number("INV-2001")
    assert_equal 1, paid.payments.count
    assert_equal BigDecimal("1000"), paid.paid_amount
    assert_equal Plutus::DebitAmount.sum(:amount), Plutus::CreditAmount.sum(:amount)
  end

  test "leaves a hand-entered payment alone on re-import" do
    @org.settings.update!(bank_account: @bank)
    csv = file_fixture("xero/invoices_with_payments.csv").read
    Imports::XeroInvoicesService.new(csv, organization: @org).call

    part = invoice_by_number("INV-2002")
    part.payments.create!(organization: @org, amount: 100, paid_on: Date.new(2026, 8, 1), bank_account: @bank)

    Imports::XeroInvoicesService.new(csv, organization: @org).call
    assert_equal 2, part.payments.count
    assert_equal BigDecimal("350"), part.reload.paid_amount
  end

  test "reports rather than records a paid amount larger than the invoice" do
    @org.settings.update!(bank_account: @bank)
    csv = file_fixture("xero/invoices_with_payments.csv").read
    result = Imports::XeroInvoicesService.new(csv, organization: @org).call

    over = invoice_by_number("INV-2004")
    assert_equal 0, over.payments.count
    assert(result.errors.any? { |e| e.include?("INV-2004") && e.match?(/lines total/) })
  end

  test "warns when a paid amount arrives with no bank account configured" do
    @org.settings.update!(bank_account: nil)
    csv = file_fixture("xero/invoices_with_payments.csv").read
    result = Imports::XeroInvoicesService.new(csv, organization: @org).call

    assert_equal 0, Payment.count
    assert(result.errors.any? { |e| e.match?(/set a bank account/i) })
  end

  test "a CSV without the payment columns imports exactly as before" do
    @org.settings.update!(bank_account: @bank)
    csv = file_fixture("xero/invoices.csv").read
    result = Imports::XeroInvoicesService.new(csv, organization: @org).call

    assert_equal 3, result.created
    assert_empty result.errors
    assert_equal 0, Payment.count
  end

  test "takes the issue date from Xero rather than the import date" do
    csv = file_fixture("xero/invoices.csv").read
    Imports::XeroInvoicesService.new(csv, organization: @org).call

    inv = invoice_by_number("INV-1001")
    assert_equal Date.new(2026, 7, 15), inv.date

    # …and the ledger entry is dated then too, so period reports line up.
    assert_equal Date.new(2026, 7, 15), inv.entries.sole.date
  end

  test "a row's BankAccount column picks the bank by code or name, Settings is the fallback" do
    @org.settings.update!(bank_account: @bank)
    chase = create_bank_account(@org, name: "Chase Business Checking")   # no code, like Xero
    csv = file_fixture("xero/invoices_with_bank.csv").read
    result = Imports::XeroInvoicesService.new(csv, organization: @org).call

    assert_equal 4, result.created
    by_number = ->(n) { invoice_by_number(n) }

    assert_equal @bank, by_number.("INV-3001").payments.sole.bank_account    # by code
    assert_equal chase, by_number.("INV-3002").payments.sole.bank_account    # by name
    assert_equal @bank, by_number.("INV-3004").payments.sole.bank_account    # blank → Settings

    # Unknown bank: the invoice still lands, the payment does not, and it says so.
    assert_equal 0, by_number.("INV-3003").payments.count
    assert(result.errors.any? { |e| e.include?("INV-3003") && e.include?("Closed Account") })
  end
end

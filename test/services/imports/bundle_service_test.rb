require "test_helper"

class Imports::BundleServiceTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @bundle = file_fixture("xero/bundle")
  end

  def invoice_by_number(n)
    Invoice.joins(:document).where(documents: { organization_id: @org.id }).find_by!(xero_invoice_number: n).document
  end

  test "runs the bundle in order and wires settings from settings.yml" do
    report = Imports::BundleService.new(@bundle, organization: @org).call

    assert_not report.failed?, report.to_s
    assert_equal [ "chart of accounts", "contacts (customers)", "sales invoices", "bills", "journals" ], report.steps.map(&:name)

    s = @org.settings.reload
    assert_equal "Accounts Receivable", s.receivable_account.name
    assert_equal "Accounts Payable",    s.payable_account.name
    assert_equal "Main Checking",       s.bank_account.name          # matched by name, no code

    assert_equal 6, @org.plutus_accounts.count
    assert_equal 2, @org.documents.invoices.count
    assert_equal 1, @org.documents.bills.count
    assert_equal 3, Payment.count

    # BankAccount on the row wins; a blank one falls back to Settings.
    assert_equal "Old Bank",      invoice_by_number("INV-1").payments.sole.bank_account.name
    assert_equal "Main Checking", invoice_by_number("INV-2").payments.sole.bank_account.name

    # journals.csv posts the conversion balance and spend money; the ACCREC journal
    # is skipped because invoices.csv already carried INV-1.
    journals = report.steps.find { |s| s.name == "journals" }.result
    assert_equal 2, journals.created, journals.errors.inspect
    assert_equal 1, journals.skipped
    assert_equal 2, @org.documents.journal_entries.count
    assert_equal BigDecimal("460"), s.bank_account.balance     # 100 opening + 500 INV-2 - 120 BILL-1 - 20 domain
    assert_equal 2, report.summary["journals"]

    assert_equal Plutus::DebitAmount.sum(:amount), Plutus::CreditAmount.sum(:amount)
    assert_match(/BALANCED/, report.summary["trial balance"])
  end

  test "re-running the same bundle updates in place" do
    Imports::BundleService.new(@bundle, organization: @org).call
    report = Imports::BundleService.new(@bundle, organization: @org).call

    assert_not report.failed?, report.to_s
    assert_equal 0, report.steps.find { |s| s.name == "sales invoices" }.result.created
    assert_equal 2, report.steps.find { |s| s.name == "sales invoices" }.result.updated
    assert_equal 2, @org.documents.invoices.count
    assert_equal 3, Payment.count
  end

  test "dry run reports the outcome and writes nothing" do
    report = Imports::BundleService.new(@bundle, organization: @org, dry_run: true).call

    assert report.dry_run
    assert_not report.failed?, report.to_s
    assert_equal 2, report.steps.find { |s| s.name == "sales invoices" }.result.created
    assert_match(/DRY RUN/, report.to_s)

    assert_equal 0, @org.plutus_accounts.count
    assert_equal 0, @org.documents.invoices.count
    assert_equal 0, Payment.count
    assert_nil @org.reload.settings&.bank_account, "dry run should not leave a settings row behind"
  end

  test "a missing chart of accounts is fatal and nothing is written" do
    Dir.mktmpdir do |dir|
      FileUtils.cp(@bundle.join("invoices.csv"), dir)
      report = Imports::BundleService.new(dir, organization: @org).call

      assert report.failed?
      assert_match(/chart_of_accounts.csv not found/, report.fatal)
      assert_equal 0, @org.documents.invoices.count
    end
  end

  test "settings.yml naming an account that isn't in the chart is fatal" do
    Dir.mktmpdir do |dir|
      FileUtils.cp(@bundle.join("chart_of_accounts.csv"), dir)
      File.write(File.join(dir, "settings.yml"), "bank_account: Closed Account\n")
      report = Imports::BundleService.new(dir, organization: @org).call

      assert report.failed?
      assert_match(/no bank account matching "Closed Account"/, report.fatal)
      assert_equal 0, @org.plutus_accounts.count, "fatal settings should roll back the chart of accounts too"
    end
  end
end

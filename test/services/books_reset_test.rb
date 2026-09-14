require "test_helper"

class BooksResetTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    Imports::BundleService.new(file_fixture("xero/bundle"), organization: @org).call
    assert_equal 2, @org.invoices.count
    assert_equal 2, @org.journal_entries.count
    assert Plutus::Entry.any?
  end

  test "transactions scope wipes documents and postings but keeps the chart" do
    report = BooksReset.new(@org, scope: :transactions).call

    assert_equal 0, @org.invoices.count
    assert_equal 0, @org.expenses.count
    assert_equal 0, Payment.count
    assert_equal 0, @org.journal_entries.count
    assert_equal 0, JournalLine.count
    assert_equal 0, LineItem.count
    assert_equal 0, Plutus::Entry.count
    assert_equal 0, Plutus::Amount.count

    assert_equal 6, @org.plutus_accounts.count
    assert_equal 2, @org.bank_accounts.count
    assert_equal 2, @org.contacts.count   # Acme (customer) and Hetzner (vendor) from the bundle
    assert_equal "Main Checking", @org.settings.reload.bank_account.name
    assert_match(/invoices\s+2 → 0/, report.to_s)
  end

  test "everything scope leaves an empty organisation with its users intact" do
    users = @org.users.count
    BooksReset.new(@org, scope: :everything).call

    assert_equal 0, @org.plutus_accounts.count
    assert_equal 0, @org.bank_accounts.count
    assert_equal 0, @org.contacts.count
    assert_equal 0, @org.tax_rates.count
    assert_nil OrganizationSettings.find_by(organization: @org)
    assert Organization.exists?(@org.id)
    assert_equal users, @org.users.count
  end

  test "dry run reports but writes nothing" do
    report = BooksReset.new(@org, scope: :everything, dry_run: true).call
    assert report.dry_run
    assert_equal 0, report.after["invoices"]
    assert_equal 2, @org.invoices.count
    assert_equal 6, @org.plutus_accounts.count
  end

  test "a reset import re-runs cleanly" do
    BooksReset.new(@org, scope: :transactions).call
    report = Imports::BundleService.new(file_fixture("xero/bundle"), organization: @org).call
    assert_not report.failed?, report.to_s
    assert_equal 2, @org.invoices.count
    assert_equal Plutus::DebitAmount.sum(:amount), Plutus::CreditAmount.sum(:amount)
  end
end

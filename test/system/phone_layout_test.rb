require "application_system_test_case"

# Every page a phone user reaches fits the screen and shows the bottom bar.
class PhoneLayoutTest < ApplicationSystemTestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @bank    = create_bank_account(@org, name: "Checking", code: "090")
    @ar      = Plutus::Asset.create!(tenant: @org, name: "Accounts Receivable", code: "1200")
    @ap      = Plutus::Liability.create!(tenant: @org, name: "Accounts Payable", code: "2000")
    @sales   = Plutus::Revenue.create!(tenant: @org, name: "Timing Services", code: "4100")
    @hosting = Plutus::Expense.create!(tenant: @org, name: "Web Hosting", code: "6820")
    @org.settings.update!(receivable_account: @ar, payable_account: @ap, bank_account: @bank)
    @invoice = create_invoice(@org, client_name: "Northwind Trail Series", amount: 5400, receivable: @ar, revenue: @sales)
    create_bill(@org, vendor: "Gusto", amount: 6459, category: @hosting, payable: @ap)
    create_expense(@org, vendor: "Blue Pixel Hosting", amount: 48, category: @hosting, bank_account: @bank)
    @org.bank_transactions.create!(bank_account: @bank, posted_on: Date.current, amount: 5400, payee: "Northwind Trail Series", description: "ACH CREDIT")
    sign_in_as_launchpad_user(@org)
    on_phone
  end

  PAGES = {
    "dashboard"      => "/",
    "invoices"       => "/invoices",
    "new invoice"    => "/invoices/new",
    "expenses"       => "/expenses",
    "bills"          => "/bills",
    "reconcile"      => "/bank_transactions",
    "reports"        => "/reports",
    "profit & loss"  => "/reports/profit_and_loss",
    "balance sheet"  => "/reports/balance_sheet",
    "contacts"       => "/contacts",
    "settings"       => "/settings"
  }.freeze

  PAGES.each do |label, path|
    test "#{label} fits a phone and shows the tab bar" do
      visit path
      assert_selector "main"
      assert_fits_viewport(label)
      assert_selector "nav.app-tabs a", minimum: 5
    end
  end

  test "an invoice page fits a phone and keeps its primary action on screen" do
    visit "/invoices/#{@invoice.id}"
    assert_fits_viewport("invoice")
    assert_selector ".action-bar", visible: true
  end
end

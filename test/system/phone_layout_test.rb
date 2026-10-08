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
      assert_selector "nav.app-tabs a, nav.app-tabs button", minimum: 5
      shoot(label)
    end
  end

  test "the More tab opens a sheet with the rest of the app, and the sidebar is gone" do
    visit "/reports"
    assert_no_selector "nav.app-nav", visible: true
    assert_no_selector ".sheet-panel", visible: true
    within("nav.app-tabs") { click_on "More" }
    within(".sheet-panel") do
      assert_link "Reports"
      assert_link "Settings"
      assert_link "Contacts"
      assert_button "Sign out"
    end
    shoot("more sheet")
    find(".sheet-dimmer").click(x: 0, y: -320)    # near the top, above the sheet
    assert_no_selector ".sheet-panel", visible: true
  end

  test "the tab for the current section is marked" do
    visit "/expenses"
    assert_selector "nav.app-tabs a[aria-current=page]", text: "Expenses", count: 1
    visit "/reports"
    assert_selector "nav.app-tabs button[aria-current=page]", text: "More", count: 1
  end

  test "a tablet keeps the sidebar as an icon rail" do
    resize_to(820, 1180)
    visit "/invoices"
    assert_fits_viewport("tablet invoices")
    assert_selector "nav.app-nav", visible: true
    assert_no_selector "nav.app-tabs", visible: true
    assert_operator find("nav.app-nav").native.size.width, :<, 80
    shoot("tablet invoices")
  end

  test "lists read as cards on a phone: no header row, key cells only" do
    visit "/invoices"
    assert_no_selector "table thead", visible: true
    within("tr##{ActionView::RecordIdentifier.dom_id(@invoice)}") do
      assert_selector "td[data-cell=primary]", text: "Northwind Trail Series", visible: true
      assert_selector "td[data-cell=amount]", text: "$5,400.00", visible: true
      assert_selector "td[data-cell=status] .badge", visible: true
      assert_selector "td[data-cell=secondary]", text: /INV-\d+/, visible: true
      assert_no_selector "td:not([data-cell])", visible: true
    end
    shoot("invoices cards")

    on_desktop
    visit "/invoices"
    assert_selector "table thead", visible: true
    assert_selector "td:not([data-cell])", visible: true
  end

  test "an invoice page fits a phone and keeps its primary action on screen" do
    visit "/invoices/#{@invoice.id}"
    assert_fits_viewport("invoice")
    assert_selector ".action-bar", visible: true
  end
end

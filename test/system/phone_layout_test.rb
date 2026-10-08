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

  test "status filters are chips and the New button floats on a phone" do
    draft = create_invoice(@org, client_name: "Summit Races", amount: 180, receivable: @ar, revenue: @sales, state: "draft")
    visit "/invoices"
    assert_selector "nav.chips a[aria-current=page]", text: "Active", count: 1
    within("nav.chips") { click_on "Draft" }
    assert_selector "nav.chips a[aria-current=page]", text: "Draft", count: 1
    assert_selector "tr##{ActionView::RecordIdentifier.dom_id(draft)}"
    assert_no_selector "tr##{ActionView::RecordIdentifier.dom_id(@invoice)}"

    fab = find("a.page-primary", text: "New invoice", visible: :all)
    assert_equal "fixed", page.evaluate_script("getComputedStyle(arguments[0]).position", fab.native)
    assert fab.visible?
    shoot("invoices chips")
  end

  test "a form on a phone is one column, lines are cards that expand, and the save bar is pinned" do
    visit "/invoices/new"
    assert_fits_viewport("new invoice")
    assert_no_selector ".line-items thead", visible: true
    # A fresh row opens with every field; Details folds it to description and amount, and back.
    row = find(".line-items tbody tr", match: :first)
    within(row) do
      assert_selector "input[name*='[description]']", visible: true
      assert_selector "input[aria-label='Amount']", visible: true
      assert_selector "select[name*='[account_id]']", visible: true
      click_on "Details"
      assert_no_selector "select[name*='[account_id]']", visible: true
      assert_no_selector "input[name*='[quantity]']", visible: true
      find("input[aria-label='Amount']").fill_in(with: "250")
      click_on "Details"
      assert_selector "input[name*='[quantity]']", visible: true
    end
    assert_selector "[data-line-items-target=total]", text: "$250.00"
    click_on "+ Add line"
    assert_selector ".line-items tbody tr", count: 2
    within(all(".line-items tbody tr").last) { assert_selector "select[name*='[account_id]']", visible: true }

    bar = find(".form-actions")
    assert_equal "fixed", page.evaluate_script("getComputedStyle(arguments[0]).position", bar.native)
    within(bar) { assert_button "Save draft"; assert_button "Approve" }
    shoot("new invoice form")

    on_desktop
    visit "/invoices/new"
    assert_selector ".line-items thead", visible: true
    assert_no_button "Details", visible: true
    assert_not_equal "fixed", page.evaluate_script("getComputedStyle(document.querySelector('.form-actions')).position")
  end

  test "reconcile on a phone: account chips with counts, a thumb-sized OK, and the panel opens under the card" do
    visit "/bank_transactions"
    assert_fits_viewport("reconcile")
    assert_selector "nav.chips a", text: "Checking · 1"
    assert_selector "nav.chips a", text: "Unmatched"
    ok = find(".suggestion .btn", text: "OK")
    assert_operator ok.native.size.height, :>=, 40
    click_on "Expense"
    assert_selector ".recon-panel", visible: true
    assert_fits_viewport("reconcile with panel")
    shoot("reconcile")
  end

  test "the dashboard on a phone: quick actions, stacked tiles, activity as cards" do
    visit "/"
    assert_selector ".quick-actions a", text: "Reconcile · 1"
    assert_selector ".quick-actions a", text: "New invoice"
    assert_no_selector ".panel table thead", visible: true
    assert_selector ".panel td[data-cell=primary]", visible: true, minimum: 1
    tiles = all(".kpi-card").map { |c| c.native.location.x }
    assert_equal 1, tiles.uniq.size, "KPI tiles stack in one column"
    shoot("dashboard")
  end

  test "a document page keeps its actions in a bar above the tabs, with the rest in a sheet" do
    visit "/invoices/#{@invoice.id}"
    assert_fits_viewport("invoice")
    bar = find(".action-bar")
    assert_equal "fixed", page.evaluate_script("getComputedStyle(arguments[0]).position", bar.native)
    within(bar) do
      assert_link "Record payment"
      assert_link "Edit"
      assert_no_link "Print / PDF"
      click_on "More actions"
    end
    within(".sheet-panel") do
      assert_link "Print / PDF"
      assert_link "Email"
      assert_button "Void"
    end
    shoot("invoice actions sheet")
    find(".sheet-dimmer").click(x: 0, y: -320)

    # Lines are cards; history is folded behind its count until tapped.
    assert_no_selector "section table thead", visible: true
    assert_selector "td[data-cell=primary]", text: "Services rendered", visible: true
    assert_no_selector ".history li", visible: true
    click_on "History · 1"
    assert_selector ".history li", visible: true, count: 1
    shoot("invoice page")

    draft = create_invoice(@org, client_name: "Summit Races", amount: 180, receivable: @ar, revenue: @sales, state: "draft")
    visit "/invoices/#{draft.id}"
    within(".action-bar") { assert_button "Approve" }

    on_desktop
    visit "/invoices/#{@invoice.id}"
    assert_not_equal "fixed", page.evaluate_script("getComputedStyle(document.querySelector('.action-bar')).position")
    assert_link "Print / PDF", visible: true
    assert_no_button "More actions", visible: true
    assert_selector ".history li", visible: true, count: 1
  end
end

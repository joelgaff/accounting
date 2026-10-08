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
    @contact = @org.contacts.create!(name: "Northwind Trail Series", kind: "customer", email: "ops@northwind.example")
    @invoice = create_invoice(@org, contact: @contact, amount: 5400, receivable: @ar, revenue: @sales)
    @bill    = create_bill(@org, vendor: "Gusto", amount: 6459, category: @hosting, payable: @ap)
    @expense = create_expense(@org, vendor: "Blue Pixel Hosting", amount: 48, category: @hosting, bank_account: @bank)
    @org.bank_transactions.create!(bank_account: @bank, posted_on: Date.current, amount: 5400, payee: "Northwind Trail Series", description: "ACH CREDIT")
    @klass = @org.tracking_categories.create!(name: "Class")
    sign_in_as_launchpad_user(@org)
    on_phone
  end

  # Every page a signed-in person can reach by GET. Paths with an id are
  # resolved against the records the setup creates.
  PAGES = {
    "dashboard"            => "/",
    "invoices"             => "/invoices",
    "new invoice"          => "/invoices/new",
    "edit invoice"         => "/invoices/%{invoice}/edit",
    "invoice"              => "/invoices/%{invoice}",
    "new payment"          => "/documents/%{invoice}/payments/new",
    "bills"                => "/bills",
    "bill"                 => "/bills/%{bill}",
    "new bill"             => "/bills/new",
    "expenses"             => "/expenses",
    "expense"              => "/expenses/%{expense}",
    "new expense"          => "/expenses/new",
    "deposits"             => "/deposits",
    "transfers"            => "/transfers",
    "journal"              => "/journal_entries",
    "new journal entry"    => "/journal_entries/new",
    "recurring invoices"   => "/recurring_invoices",
    "new recurring"        => "/recurring_invoices/new",
    "contacts"             => "/contacts",
    "contact"              => "/contacts/%{contact}",
    "new contact"          => "/contacts/new",
    "accounts"             => "/accounts",
    "banking"              => "/bank_accounts",
    "bank account"         => "/bank_accounts/%{bank}",
    "reconcile"            => "/bank_transactions",
    "bank rules"           => "/bank_rules",
    "new bank rule"        => "/bank_rules/new",
    "reports"              => "/reports",
    "profit & loss"        => "/reports/profit_and_loss",
    "balance sheet"        => "/reports/balance_sheet",
    "trial balance"        => "/reports/trial_balance",
    "general ledger"       => "/reports/general_ledger",
    "receivables aging"    => "/reports/accounts_receivable_aging",
    "payables aging"       => "/reports/accounts_payable_aging",
    "settings"             => "/settings",
    "people"               => "/settings/people",
    "bank feed"            => "/settings/bank_feed",
    "tax rates"            => "/settings/tax_rates",
    "tracking categories"  => "/settings/tracking_categories",
    "xero"                 => "/settings/xero",
    "imports"              => "/imports"
  }.freeze

  def resolve(path)
    format(path, invoice: @invoice.id, bill: @bill.id, expense: @expense.id, contact: @contact.id, bank: @bank.id)
  end

  PAGES.each do |label, path|
    test "#{label} fits a phone and shows the tab bar" do
      visit resolve(path)
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

  test "a remembered payee gets a one-tap OK on a phone, and the tap codes the line" do
    3.times do |i|
      t = @org.bank_transactions.create!(bank_account: @bank, posted_on: Date.new(2026, 7 + i, 2), amount: -15, description: "ZOOM.US 888-799-9666")
      Reconciliation::Categorize.new(t, account: @hosting, contact_name: "Zoom").call
    end
    fresh = @org.bank_transactions.create!(bank_account: @bank, posted_on: Date.current, amount: -15, description: "ZOOM.US 888-799-9666")
    visit "/bank_transactions?status=unmatched"
    row = find("##{ActionView::RecordIdentifier.dom_id(fresh)}")
    within(row) do
      assert_selector ".suggestion-text", text: /Expense · Zoom/
      assert_selector ".suggestion .coding", text: /Web Hosting/, visible: true
      ok = find(".suggestion .btn", text: "OK")
      assert_operator ok.native.size.height, :>=, 40
      ok.click
    end
    assert_selector "##{ActionView::RecordIdentifier.dom_id(fresh)} .badge-matched", wait: 5
    assert_selector "##{ActionView::RecordIdentifier.dom_id(fresh)} .recon-actions .coding", text: /Web Hosting/, visible: true
    assert_equal "Zoom", fresh.reload.document.counterparty
    assert_fits_viewport("reconcile after memory OK")
    shoot("reconcile memory ok")
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

  test "reports on a phone: the balance sheet stacks, wide tables freeze the account column" do
    visit "/reports/balance_sheet"
    assert_fits_viewport("balance sheet")
    columns = all(".report-columns > *").map { |c| c.native.location.x }
    assert_equal 1, columns.uniq.size, "assets and liabilities stack"

    visit "/reports/profit_and_loss_by_tracking"
    assert_fits_viewport("P&L by tracking")
    cell = find("table.frozen-first tbody tr td[data-frozen]", match: :first)
    assert_equal "sticky", page.evaluate_script("getComputedStyle(arguments[0]).position", cell.native)
    shoot("tracking pnl")

    on_desktop
    visit "/reports/balance_sheet"
    columns = all(".report-columns > *").map { |c| c.native.location.x }
    assert_equal 2, columns.uniq.size, "side by side on a desktop"
  end

  test "a contact's activity reads as cards and the trial balance keeps the account in view" do
    visit "/contacts/#{@contact.id}"
    assert_no_selector "table thead", visible: true
    assert_selector "td[data-cell=primary]", text: /Invoice INV-/, visible: true
    visit "/reports/trial_balance"
    cell = find("table.frozen-first tbody tr td[data-frozen]", match: :first)
    assert_equal "sticky", page.evaluate_script("getComputedStyle(arguments[0]).position", cell.native)
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

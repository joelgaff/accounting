require "test_helper"

class TrackingTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @year  = @org.tracking_categories.create!(name: "Event Year", options_attributes: [ { name: "2025" }, { name: "2026" } ])
    @klass = @org.tracking_categories.create!(name: "Class", options_attributes: [ { name: "EE Timing" }, { name: "IRONMAN" } ])
    @ar    = Plutus::Asset.create!(tenant: @org, name: "AR")
    @sales = Plutus::Revenue.create!(tenant: @org, name: "Sales")
    @bank  = create_bank_account(@org, name: "Bank")
  end

  def opt(category, name) = category.options.find_by!(name: name)

  test "at most two categories are active at once" do
    third = @org.tracking_categories.build(name: "Region", active: true)
    assert_not third.valid?
    assert third.errors[:active].any?
    third.active = false
    assert third.valid?
  end

  test "a line takes one option per category and the last one per category wins" do
    inv  = create_invoice(@org, client_name: "A", amount: 10, receivable: @ar, revenue: @sales)
    line = inv.line_items.sole
    line.update!(tracking_option_ids: [ opt(@year, "2025").id, opt(@year, "2026").id, opt(@klass, "IRONMAN").id ])
    line.reload
    assert_equal "2026",    line.tracking_option_for(@year).name
    assert_equal "IRONMAN", line.tracking_option_for(@klass).name
    assert_equal 2, line.tracking_selections.count

    line.update!(tracking_option_ids: [ opt(@klass, "EE Timing").id ])
    line.reload
    assert_nil line.tracking_option_for(@year)
    assert_equal "EE Timing", line.tracking_option_for(@klass).name
  end

  test "documents created from forms carry tracking through nested attributes" do
    inv = @org.documents.create!(date: Date.current, documentable: Invoice.new(client_name: "A", due_date: Date.current + 30, receivable_account: @ar),
      line_items_attributes: [ { description: "x", quantity: 1, unit_amount: 100, account_id: @sales.id, tracking_option_ids: [ "", opt(@year, "2026").id.to_s ] } ])
    assert_equal "2026", inv.line_items.sole.tracking_option_for(@year).name
  end

  test "recurring invoices copy tracking to the invoices they generate" do
    ri = @org.recurring_invoices.create!(client_name: "Acme", receivable_account: @ar, frequency: "monthly", interval: 1, next_run_on: Date.current,
      line_items_attributes: [ { description: "Retainer", quantity: 1, unit_amount: 500, account_id: @sales.id, tracking_option_ids: [ opt(@klass, "EE Timing").id ] } ])
    invoice = ri.generate!(as_of: Date.current)
    assert_equal "EE Timing", invoice.line_items.sole.tracking_option_for(@klass).name
  end

  test "reconcile categorize and bank rules pin tracking on the new line" do
    hosting = Plutus::Expense.create!(tenant: @org, name: "Hosting")
    txn  = @org.bank_transactions.create!(bank_account: @bank, posted_on: Date.current, amount: -30, description: "HOST")
    Reconciliation::Categorize.new(txn, account: hosting, tracking_option_ids: [ opt(@klass, "IRONMAN").id ]).call
    assert_equal "IRONMAN", txn.reload.document.line_items.sole.tracking_option_for(@klass).name

    rule = @org.bank_rules.create!(name: "CF", pattern: "cloudflare", action_kind: "Expense", account: hosting, tracking_option_ids: [ opt(@year, "2026").id ])
    txn2 = @org.bank_transactions.create!(bank_account: @bank, posted_on: Date.current, amount: -8, payee: "CLOUDFLARE", description: "x")
    rule.apply!(txn2)
    assert_equal "2026", txn2.reload.document.line_items.sole.tracking_option_for(@year).name
  end

  test "a Xero export creates categories and options on first sight" do
    @org.tracking_categories.destroy_all
    @org.settings.update!(receivable_account: @ar)
    Plutus::Revenue.create!(tenant: @org, name: "Ops", code: "200")
    Plutus::Revenue.create!(tenant: @org, name: "Timing", code: "210")
    result = Imports::XeroInvoicesService.new(file_fixture("xero/invoices_with_tracking.csv").read, organization: @org).call
    assert_equal 2, result.created, result.errors.inspect
    year  = @org.tracking_categories.find_by!(name: "Event Year")
    klass = @org.tracking_categories.find_by!(name: "Class")
    assert_equal %w[2026], year.options.pluck(:name)
    assert_equal [ "EE Timing", "IRONMAN" ], klass.options.pluck(:name).sort
    timing = LineItem.find_by!(description: "Timing", unit_amount: 1500)
    assert_equal "EE Timing", timing.tracking_option_for(klass).name
  end

  test "P&L by tracking splits lines by option and matches the ledger total" do
    hosting = Plutus::Expense.create!(tenant: @org, name: "Hosting")
    @org.documents.create!(date: Date.current, documentable: Invoice.new(client_name: "A", due_date: Date.current + 30, receivable_account: @ar),
      line_items_attributes: [ { description: "a", quantity: 1, unit_amount: 1000, account_id: @sales.id, tracking_option_ids: [ opt(@klass, "IRONMAN").id ] },
                               { description: "b", quantity: 1, unit_amount: 500,  account_id: @sales.id, tracking_option_ids: [ opt(@klass, "EE Timing").id ] },
                               { description: "c", quantity: 1, unit_amount: 25,   account_id: @sales.id } ])
    create_expense(@org, vendor: "DO", amount: 200, category: hosting, bank_account: @bank)
    @org.documents.create!(date: Date.current, documentable: JournalEntry.new(narrative: "Adj",
      lines_attributes: [ { account_id: hosting.id, debit_amount: 40, tracking_option_ids: [ opt(@klass, "IRONMAN").id ] }, { account_id: @bank.account.id, credit_amount: 40 } ]))

    r = Reports::ProfitAndLossByTracking.new(organization: @org, category: @klass)
    ironman  = opt(@klass, "IRONMAN"); timing = opt(@klass, "EE Timing"); none = Reports::ProfitAndLossByTracking::UNASSIGNED
    assert_equal BigDecimal("1000"), r.column_total(r.revenue_rows, ironman)
    assert_equal BigDecimal("500"),  r.column_total(r.revenue_rows, timing)
    assert_equal BigDecimal("25"),   r.column_total(r.revenue_rows, none)
    assert_equal BigDecimal("40"),   r.column_total(r.expense_rows, ironman)
    assert_equal BigDecimal("200"),  r.column_total(r.expense_rows, none)
    assert_equal BigDecimal("960"),  r.net_income(ironman)
    assert_equal r.ledger_net_income, r.total_revenue - r.total_expenses

    # A refund received against an expense account reduces that expense, as in the ledger.
    @org.documents.create!(date: Date.current, documentable: Deposit.new(bank_account: @bank),
      line_items_attributes: [ { description: "refund", quantity: 1, unit_amount: 50, account_id: hosting.id, tracking_option_ids: [ opt(@klass, "IRONMAN").id ] } ])
    r = Reports::ProfitAndLossByTracking.new(organization: @org, category: @klass)
    assert_equal BigDecimal("-10"), r.column_total(r.expense_rows, ironman)
    assert_equal r.ledger_net_income, r.total_revenue - r.total_expenses
  end
end

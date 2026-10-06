require "test_helper"

class Xero::ImportTest < ActiveSupport::TestCase
  setup do
    @org  = organizations(:one)
    @conn = @org.create_xero_connection!(tenant_id: "tenant-1", tenant_name: "EE", access_token: "at", refresh_token: "rt", token_expires_at: 1.hour.from_now)
    @client = Xero::Client.new(@conn, transport: FakeXero.new, pause: 0)
  end

  test "pulls the whole organisation from the api with tracking and payments, idempotently" do
    Xero::Import.new(@conn, client: @client).call
    @conn.reload
    assert_equal "done", @conn.status
    assert_equal %w[chart\ of\ accounts tax\ rates contacts\ (customers) contacts\ (vendors) contacts\ (both) tracking\ categories sales\ invoices bills spend\ and\ receive\ money transfers manual\ journals], @conn.steps.map { |s| s["step"] }
    assert @conn.steps.all? { |s| s["done"] }, @conn.steps.inspect
    errs = @conn.steps.flat_map { |s| s["errors"] }
    assert_equal 1, errs.size, errs.inspect
    extra = Invoice.find_by!(xero_invoice_number: "INV-4002").document
    assert_equal BigDecimal("250"), extra.total, "3 × 83.3333 lands on Xero's line total, not 249.99"
    assert_equal BigDecimal("3"), extra.line_items.sole.quantity, "quantity kept because it multiplies out to the cent"

    # chart, with Xero's own idea of which bank is a card, and Settings pointed at the control accounts
    assert_equal 9, @org.plutus_accounts.count, "archived account skipped"
    assert @org.bank_accounts.find_by_code_or_name("2069").credit_card?
    assert_equal "checking", @org.bank_accounts.find_by_code_or_name("1140").kind
    assert_equal "Accounts Receivable", @org.settings.receivable_account.name
    assert_equal "Accounts Payable",    @org.settings.payable_account.name

    assert_equal [ "Sales Tax", "Tax Exempt" ], @org.tax_rates.pluck(:name).sort
    assert_equal %w[customer vendor both], [ @org.contacts.find_by!(name: "IRONMAN").kind, @org.contacts.find_by!(name: "Williams Pumping").kind, @org.contacts.find_by!(name: "Both Ways LLC").kind ]
    assert_nil @org.contacts.find_by(name: "Archived Co")
    assert_equal "Tampa", @org.contacts.find_by!(name: "IRONMAN").city

    klass = @org.tracking_categories.find_by!(name: "Class")
    year  = @org.tracking_categories.find_by!(name: "Event Year")
    assert klass.active? && year.active?
    assert_equal [ "EE Timing", "IRONMAN", "z Old" ], klass.options.pluck(:name).sort
    assert_not klass.options.find_by!(name: "z Old").active?

    inv = Invoice.find_by!(xero_invoice_number: "INV-4001").document
    assert_equal "Invoice INV-4001", inv.label
    assert_equal BigDecimal("5500"), inv.total
    assert_equal "IRONMAN", inv.counterparty
    assert_equal [ "IRONMAN", "EE Timing" ], inv.line_items.order(:id).map { |l| l.tracking_option_for(klass).name }
    assert_equal "2026", inv.line_items.first.tracking_option_for(year).name
    assert inv.paid?
    assert_equal "PNC Checking", inv.payments.sole.bank_account.name
    assert_equal Date.new(2026, 7, 29), inv.payments.sole.paid_on
    assert_nil Invoice.find_by(xero_invoice_number: "INV-0001"), "voided invoice not imported"
    assert_equal 2, @org.documents.invoices.count

    bill = Bill.find_by!(xero_invoice_number: "0b100000-0000-4000-8000-000000000001").document
    assert_equal "Bill 79738R", bill.label
    assert_equal BigDecimal("917.64"), bill.total
    assert bill.paid?, "a total a few cents above the lines still settles"
    assert_equal "IRONMAN", bill.line_items.sole.tracking_option_for(klass).name
    assert_equal 2, Bill.where(number: "79738R").count, "the same vendor number in two years stays two bills"
    assert_match(/recorded 917\.64/, @conn.steps.find { |s| s["step"] == "bills" }["errors"].join)
    unnumbered = Bill.find_by!(xero_invoice_number: "b2c3d4e5-0000-0000-0000-000000000000").document
    assert_equal "Bill ##{unnumbered.id}", unnumbered.label, "a made-up Xero key is not shown as a number"
    assert unnumbered.paid?
    assert_equal "Chase United", unnumbered.payments.sole.bank_account.name

    cones = Expense.find_by!(xero_id: "bt1").document
    assert_equal "Expense", cones.documentable_type
    assert_equal "Williams Pumping", cones.counterparty
    assert_equal "PNC Checking", cones.expense.bank_account.name
    assert_equal BigDecimal("80"), cones.total
    assert_equal [ BigDecimal("4"), BigDecimal("20") ], [ cones.line_items.sole.quantity, cones.line_items.sole.unit_amount ]
    assert_equal "IRONMAN", cones.line_items.sole.tracking_option_for(klass).name
    assert_equal "xero_import", cones.source

    hats = Deposit.find_by!(xero_id: "bt2").document
    assert_equal BigDecimal("106"), hats.total, "tax-inclusive receive money lands on the gross"
    assert_equal BigDecimal("100"), hats.subtotal
    assert_equal "Sales Tax", hats.line_items.sole.tax_rate.name
    assert_equal "Sales Tax", @org.tax_rates.find_by!(name: "Sales Tax").liability_account.name, "sales tax points at Xero's tax control account"
    assert_equal BigDecimal("6"), @org.plutus_accounts.find_by!(code: "2200").balance
    assert_equal 1, @org.documents.expenses.count, "transfer-type and deleted bank transactions are not expenses"
    assert_equal 1, @org.documents.deposits.count

    transfer = Transfer.find_by!(xero_id: "tr1").document
    assert_equal BigDecimal("500"), transfer.total
    assert_equal [ "PNC Checking", "Chase United" ], [ transfer.transfer.from_bank_account.name, transfer.transfer.to_bank_account.name ]

    journal = @org.documents.journal_entries.sole
    assert_equal "MJ-mj1", journal.journal_entry.xero_journal_number, "only the posted manual journal"
    assert_equal "IRONMAN", journal.journal_entry.lines.find_by!(account: @org.plutus_accounts.find_by!(code: "3000")).tracking_option_for(klass).name

    debits  = Plutus::DebitAmount.joins(:account).where(plutus_accounts: { tenant_id: @org.id }).sum(:amount)
    credits = Plutus::CreditAmount.joins(:account).where(plutus_accounts: { tenant_id: @org.id }).sum(:amount)
    assert_equal debits, credits
    assert_match(/BALANCED/, @conn.summary["trial balance"])

    Xero::Import.new(@conn, client: @client).call
    @conn.reload
    assert_equal 2, @org.documents.invoices.count
    assert_equal 1, @org.documents.journal_entries.count
    assert_equal 1, @org.documents.expenses.count
    assert_equal 1, @org.documents.transfers.count
    assert_equal 1, inv.reload.payments.count
    assert_equal 0, @conn.steps.find { |s| s["step"] == "sales invoices" }["created"]
    assert_equal 2, @conn.steps.find { |s| s["step"] == "sales invoices" }["updated"]
  end

  test "an api failure marks the connection failed and keeps the message" do
    broken = Object.new
    broken.define_singleton_method(:get) { |*, **| raise Xero::Error, "Xero Accounts failed (401)" }
    assert_raises(Xero::Error) { Xero::Import.new(@conn, client: broken).call }
    assert_equal "failed", @conn.reload.status
    assert_match(/401/, @conn.last_error)
  end

  test "a from date limits invoices and journals" do
    Xero::Import.new(@conn, client: @client, from: Date.new(2026, 7, 15)).call
    assert_equal 1, @org.documents.invoices.count, "only INV-4002 is on or after the date"
    assert_equal 0, @org.documents.bills.count, "every bill is before the date"
    assert_equal 0, @org.documents.journal_entries.count, "the manual journal is before the date (the fake honours Date>= on every collection)"
  end
end

class Xero::ImportRekeyTest < ActiveSupport::TestCase
  setup do
    @org  = organizations(:one)
    @conn = @org.create_xero_connection!(tenant_id: "tenant-1", tenant_name: "EE", access_token: "at", refresh_token: "rt", token_expires_at: 1.hour.from_now)
    @client = Xero::Client.new(@conn, transport: FakeXero.new, pause: 0)
  end

  test "bills keyed by number from an earlier import make way for the api's copies, unless touched by hand" do
    Xero::Import.new(@conn, client: @client).call   # chart, settings, contacts in place
    ap   = @org.settings.payable_account
    cost = @org.plutus_accounts.find_by!(code: "6817")
    bank = @org.bank_accounts.find_by_code_or_name("1140")
    merged = @org.documents.create!(date: Date.new(2025, 6, 26), source: "xero_import", documentable: Bill.new(vendor: "Williams Pumping", payable_account: ap, xero_invoice_number: "79738R", number: "79738R"),
      line_items_attributes: [ { description: "2025", quantity: 1, unit_amount: 500, account_id: cost.id }, { description: "2026", quantity: 12, unit_amount: 76.47, account_id: cost.id } ])
    merged.payments.create!(organization: @org, amount: 500, paid_on: Date.new(2025, 7, 3), bank_account: bank, reference: Imports::XeroTransactionsService::PAYMENT_REFERENCE)
    hand = @org.documents.create!(date: Date.new(2024, 1, 1), source: "xero_import", documentable: Bill.new(vendor: "Someone", payable_account: ap, xero_invoice_number: "KEEP-1", number: "KEEP-1"),
      line_items_attributes: [ { description: "x", quantity: 1, unit_amount: 10, account_id: cost.id } ])
    hand.payments.create!(organization: @org, amount: 10, paid_on: Date.new(2024, 1, 2), bank_account: bank, reference: "typed in")

    Xero::Import.new(@conn, client: @client).call
    assert_nil Document.find_by(id: merged.id), "the number-keyed bill is gone"
    assert Document.exists?(hand.id), "a bill with a hand-recorded payment stays"
    assert_equal 2, Bill.where(number: "79738R").count
    assert_equal [ "0b100000-0000-4000-8000-000000000001", "0b100000-0000-4000-8000-000000000003" ], Bill.where(number: "79738R").order(:xero_invoice_number).pluck(:xero_invoice_number)
    assert_equal 4, @org.documents.bills.count   # b1, b2, b3 from the api + the hand-paid one
    debits  = Plutus::DebitAmount.joins(:account).where(plutus_accounts: { tenant_id: @org.id }).sum(:amount)
    credits = Plutus::CreditAmount.joins(:account).where(plutus_accounts: { tenant_id: @org.id }).sum(:amount)
    assert_equal debits, credits
  end
end

require "test_helper"

class BankTransactionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @org = organizations(:one)
    sign_in_as_launchpad_user(@org)
    @checking = create_bank_account(@org, name: "Checking", code: "090")
    @savings  = create_bank_account(@org, name: "Savings", code: "091", kind: "savings")
    @ar       = Plutus::Asset.create!(tenant: @org, name: "AR")
    @sales    = Plutus::Revenue.create!(tenant: @org, name: "Sales")
    @hosting  = Plutus::Expense.create!(tenant: @org, name: "Hosting")
  end

  def line(amount, bank: @checking, on: Date.current, description: "LINE", payee: "")
    @org.bank_transactions.create!(bank_account: bank, posted_on: on, amount: amount, description: description, payee: payee)
  end

  def counter_id = ActionView::RecordIdentifier.dom_id(@org, :unmatched_count)
  def row_id(txn) = ActionView::RecordIdentifier.dom_id(txn)

  test "index renders every unmatched line with its panels and one contact datalist" do
    create_invoice(@org, client_name: "Acme", amount: 100, receivable: @ar, revenue: @sales)
    @org.contacts.create!(name: "Acme", kind: "customer")
    line(100); line(-30)
    get bank_transactions_path
    assert_response :success
    assert_select "datalist option[value=Acme]", 1
    assert_select "button[data-segment=match]", 1
    assert_select "button[data-segment=create]", 2
    assert_select "##{counter_id}", text: "2"
  end

  test "match streams the row back as matched and updates the counter" do
    inv = create_invoice(@org, client_name: "Acme", amount: 100, receivable: @ar, revenue: @sales)
    txn = line(100)
    post match_bank_transaction_path(txn), params: { document_id: inv.id }, as: :turbo_stream
    assert_response :success
    assert_match(/turbo-stream action="replace" target="#{row_id(txn)}"/, response.body)
    assert_match(/turbo-stream action="update" target="#{counter_id}"/, response.body)
    assert_match(/Invoice #\d+ \$100\.00/, response.body)
    assert inv.reload.paid?
  end

  test "categorize with a tax rate and a new contact" do
    taxa = Plutus::Asset.create!(tenant: @org, name: "GST Recoverable")
    rate = @org.tax_rates.create!(name: "GST", rate: 0.1, asset_account: taxa)
    txn  = line(-110, description: "HETZNER")
    post categorize_bank_transaction_path(txn), params: { account_id: @hosting.id, tax_rate_id: rate.id, contact_name: "Hetzner" }, as: :turbo_stream
    assert_response :success
    exp = @org.documents.expenses.sole
    assert_equal "Hetzner", exp.contact.name
    assert_equal BigDecimal("110"), exp.total
    assert_equal BigDecimal("100"), @hosting.balance
    assert_equal BigDecimal("10"),  taxa.balance
  end

  test "transfer replaces both rows when the mirror line exists" do
    out = line(-500); inn = line(500, bank: @savings, on: Date.current + 1)
    post transfer_bank_transaction_path(out), params: { other_bank_account_id: @savings.id }, as: :turbo_stream
    assert_response :success
    assert_match(/target="#{row_id(out)}"/, response.body)
    assert_match(/target="#{row_id(inn)}"/, response.body)
    assert_equal "matched", inn.reload.status
    assert_equal 1, @org.documents.transfers.count
  end

  test "ignore then undo" do
    txn = line(-5)
    post ignore_bank_transaction_path(txn), as: :turbo_stream
    assert_equal "ignored", txn.reload.status
    assert_match(/Undo/, response.body)
    post unmatch_bank_transaction_path(txn), as: :turbo_stream
    assert_equal "unmatched", txn.reload.status
  end

  test "a mismatch renders an error into the row instead of a 500" do
    exp = create_expense(@org, vendor: "DO", amount: 20, category: @hosting, bank_account: @checking)
    txn = line(20)   # money in, but an expense is money out
    post match_bank_transaction_path(txn), params: { document_id: exp.id }, as: :turbo_stream
    assert_response :unprocessable_entity
    assert_match(/only matches money out/, response.body)
    assert txn.reload.unmatched?
  end

  test "index queries do not grow with the number of rows" do
    create_invoice(@org, client_name: "Acme", amount: 100, receivable: @ar, revenue: @sales)
    3.times { |i| line(100, description: "A#{i}") }
    few = count_queries { get bank_transactions_path }
    12.times { |i| line(100, description: "B#{i}") }
    many = count_queries { get bank_transactions_path }
    assert_operator many - few, :<=, 2, "expected roughly constant queries, got #{few} then #{many}"
  end

  test "one-click OK accepts a document suggestion and a transfer pair" do
    inv = create_invoice(@org, client_name: "Acme", amount: 100, receivable: @ar, revenue: @sales)
    txn = line(100, description: "ACME")
    get bank_transactions_path
    assert_select ".suggestion", 1
    post accept_suggestion_bank_transaction_path(txn), params: { kind: "document", target_id: inv.id }, as: :turbo_stream
    assert_response :success
    assert inv.reload.paid?

    out = line(-40); inn = line(40, bank: @savings)
    post accept_suggestion_bank_transaction_path(out), params: { kind: "transfer_pair", target_id: inn.id }, as: :turbo_stream
    assert_response :success
    assert inn.reload.matched?
    assert_match(/target="#{ActionView::RecordIdentifier.dom_id(@savings, :recon_summary)}"/, response.body)
  end

  test "allocate splits, and undo brings a matched line back" do
    a = create_invoice(@org, client_name: "A", amount: 60, receivable: @ar, revenue: @sales)
    b = create_invoice(@org, client_name: "B", amount: 40, receivable: @ar, revenue: @sales)
    txn = line(100)
    post allocate_bank_transaction_path(txn), params: { allocations: { "0" => { document_id: a.id, amount: "60" }, "1" => { document_id: b.id, amount: "40" } } }, as: :turbo_stream
    assert_response :success
    assert txn.reload.matched?
    assert_match(/Undo/, response.body)
    post unmatch_bank_transaction_path(txn), as: :turbo_stream
    assert_response :success
    assert txn.reload.unmatched?
    assert_equal 0, Payment.count
  end

  test "bank rules can be created from a line and edited" do
    txn = line(-8, payee: "CLOUDFLARE")
    get new_bank_rule_path(bank_transaction_id: txn.id)
    assert_response :success
    assert_select "input[name='bank_rule[pattern]'][value=CLOUDFLARE]"
    post bank_rules_path, params: { bank_rule: { name: "CF", match_kind: "contains", pattern: "cloudflare", amount_sign: "out", action_kind: "Expense", account_id: @hosting.id, auto_apply: "1", active: "1" } }
    assert_redirected_to bank_rules_path
    rule = @org.bank_rules.sole
    get bank_rules_path
    assert_select "td", text: "CF"
    patch bank_rule_path(rule), params: { bank_rule: { name: "Cloudflare" } }
    assert_equal "Cloudflare", rule.reload.name
    get bank_transactions_path
    assert_select ".suggestion", text: /Rule/
    delete bank_rule_path(rule)
    assert_equal 0, @org.bank_rules.count
  end

  private

  def count_queries
    n = 0
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, payload| n += 1 unless payload[:name] == "SCHEMA" }
    yield
    n
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end
end

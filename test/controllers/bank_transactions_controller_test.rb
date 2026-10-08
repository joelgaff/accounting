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

  # ── Memory: what a payee was coded to before ──────────────────────────────

  def coded(description, account:, on:, contact: "Blue Pixel Hosting", amount: -48, tracking: [])
    txn = line(amount, on: on, description: description)
    Reconciliation::Categorize.new(txn, account: account, contact_name: contact, tracking_option_ids: tracking).call
    txn
  end

  test "a payee coded the same way three times gets a one-tap OK that creates the expense" do
    klass  = @org.tracking_categories.create!(name: "Class")
    timing = klass.options.create!(name: "Timing")
    3.times { |i| coded("BLUEPIXEL HOSTING 0#{7 + i}/02", account: @hosting, on: Date.new(2026, 7 + i, 2), tracking: [ timing.id ]) }
    fresh = line(-48, description: "BLUEPIXEL HOSTING 10/02")

    get bank_transactions_path(status: "unmatched")
    assert_select "##{row_id(fresh)} .suggestion-text", text: /Expense · Blue Pixel Hosting/
    assert_select "##{row_id(fresh)} .suggestion .coding-account", text: "Hosting"
    assert_select "##{row_id(fresh)} .suggestion .coding-tracking", text: "Timing"
    assert_select "##{row_id(fresh)} .suggestion input[name=kind][value=memory]"

    post accept_suggestion_bank_transaction_path(fresh), params: { kind: "memory" }, as: :turbo_stream
    assert_response :success
    fresh.reload
    assert_equal "matched", fresh.status
    doc = fresh.document
    assert doc.expense?
    assert_equal @hosting, doc.line_items.sole.account
    assert_equal "Blue Pixel Hosting", doc.counterparty
    assert_equal [ timing.id ], doc.line_items.sole.tracking_option_ids
    assert_equal BigDecimal("48"), doc.total
    assert_match(/target="#{row_id(fresh)}"/, response.body)
    created = doc.events.find_by!(action: "created")
    assert_equal "memory", created.details["via"]
    assert_equal "Created from a bank line, coded from memory", created.title
  end

  test "a payee seen fewer times gets no OK, but the create panel and a new rule come prefilled" do
    coded("AMZN MKTP US*2K3", account: @hosting, on: Date.new(2026, 9, 1), contact: "Amazon")
    fresh = line(-20, description: "AMZN MKTP US*1A1")

    get bank_transactions_path(status: "unmatched")
    assert_select "##{row_id(fresh)} .suggestion", 0
    assert_select "##{row_id(fresh)} [data-segment=create] select[name=account_id] option[selected][value=?]", @hosting.id.to_s
    assert_select "##{row_id(fresh)} [data-segment=create] input[name=contact_name][value=Amazon]"

    get new_bank_rule_path(bank_transaction_id: fresh.id)
    assert_select "select[name='bank_rule[account_id]'] option[selected][value=?]", @hosting.id.to_s
  end

  test "a card shows the account and tracking behind a suggestion, and behind a matched line" do
    klass  = @org.tracking_categories.create!(name: "Class")
    timing = klass.options.create!(name: "Timing")

    # a document match: the open invoice's own account and tracking
    inv = create_invoice(@org, client_name: "Acme", amount: 100, receivable: @ar, revenue: @sales)
    inv.line_items.sole.update!(tracking_option_ids: [ timing.id ])
    paid = line(100, description: "ACME PAYMENT")
    # a memory suggestion: the remembered account and tracking
    3.times { |i| coded("ZOOM.US", account: @hosting, on: Date.new(2026, 7 + i, 1), contact: "Zoom", amount: -15, tracking: [ timing.id ]) }
    zoom = line(-15, description: "ZOOM.US")

    get bank_transactions_path(status: "unmatched")
    assert_select "##{row_id(paid)} .suggestion .coding", text: /Sales/
    assert_select "##{row_id(paid)} .suggestion .coding", text: /Timing/
    assert_select "##{row_id(zoom)} .suggestion .coding", text: /Hosting/
    assert_select "##{row_id(zoom)} .suggestion .coding", text: /Timing/

    # once matched, the result line carries the same
    post accept_suggestion_bank_transaction_path(zoom), params: { kind: "memory" }, as: :turbo_stream
    assert_match(/coding-account">Hosting</, response.body)
    get bank_transactions_path(status: "matched")
    assert_select "##{row_id(zoom)} .recon-actions .coding", text: /Hosting/
    assert_select "##{row_id(zoom)} .recon-actions .coding", text: /Timing/
  end

  test "a person can hide a bank account's summary card and bring the hidden ones back" do
    get bank_transactions_path
    assert_select "##{ActionView::RecordIdentifier.dom_id(@checking, :recon_summary)}"
    assert_select "##{ActionView::RecordIdentifier.dom_id(@savings, :recon_summary)}"
    assert_select ".recon-summary .hidden-cards", text: ""     # the empty note is the stream's target

    patch card_visibility_bank_transactions_path, params: { bank_account_id: @savings.id, hidden: "1" }, as: :turbo_stream
    assert_response :success
    assert_match(/action="remove" target="#{ActionView::RecordIdentifier.dom_id(@savings, :recon_summary)}"/, response.body)
    user = User.find_by!(launchpad_public_id: "u-#{@org.id}")
    assert_equal [ @savings.id ], user.reload.hidden_reconcile_card_ids

    get bank_transactions_path
    assert_select "##{ActionView::RecordIdentifier.dom_id(@savings, :recon_summary)}", 0
    assert_select "##{ActionView::RecordIdentifier.dom_id(@checking, :recon_summary)}"
    assert_select ".recon-summary .hidden-cards", text: /1 hidden/
    assert_select "nav.chips a", { text: /Savings/, count: 1 }, "the account chip stays; only the card goes"

    patch card_visibility_bank_transactions_path, params: { bank_account_id: @savings.id, hidden: "0" }
    assert_redirected_to bank_transactions_path
    assert_equal [], user.reload.hidden_reconcile_card_ids
    get bank_transactions_path
    assert_select "##{ActionView::RecordIdentifier.dom_id(@savings, :recon_summary)}"
  end

  test "the create panel asks why, and the answer lands on the expense" do
    txn = line(-48, description: "BLUEPIXEL HOSTING 10/02")
    get bank_transactions_path
    assert_select "##{row_id(txn)} [data-segment=create] input[name=memo][placeholder]"

    post categorize_bank_transaction_path(txn), params: { account_id: @hosting.id, memo: "Monthly hosting" }, as: :turbo_stream
    assert_response :success
    doc = txn.reload.document
    assert_equal "Monthly hosting", doc.memo
    assert_equal "Monthly hosting", doc.line_items.sole.description
  end

  test "the create panel comes prefilled with last time's why, and a memory OK carries it" do
    3.times { |i| t = line(-48, on: Date.new(2026, 7 + i, 2), description: "BLUEPIXEL HOSTING 0#{7 + i}/02"); Reconciliation::Categorize.new(t, account: @hosting, contact_name: "Blue Pixel Hosting", memo: "Monthly hosting").call }
    fresh = line(-48, description: "BLUEPIXEL HOSTING 10/02")
    get bank_transactions_path(status: "unmatched")
    assert_select "##{row_id(fresh)} [data-segment=create] input[name=memo][value='Monthly hosting']"

    post accept_suggestion_bank_transaction_path(fresh), params: { kind: "memory" }, as: :turbo_stream
    doc = fresh.reload.document
    assert_equal "Monthly hosting", doc.memo
    assert_equal "Monthly hosting", doc.line_items.sole.description
  end

  test "a matched line shows its why where the lines are read" do
    txn = line(-48, description: "BLUEPIXEL HOSTING 10/02")
    post categorize_bank_transaction_path(txn), params: { account_id: @hosting.id, memo: "Monthly hosting" }, as: :turbo_stream
    get bank_transactions_path(status: "matched")
    assert_select "##{row_id(txn)} .recon-actions .why", text: "Monthly hosting"

    get expenses_path
    assert_select "tr##{ActionView::RecordIdentifier.dom_id(txn.reload.document)} td[data-cell=secondary]", text: "Monthly hosting"

    get bank_account_path(@checking)
    assert_select ".why", text: "Monthly hosting"

    # the bank's own words are not a why, so nothing is repeated
    plain = line(-20, description: "AMZN MKTP US*2K3")
    post categorize_bank_transaction_path(plain), params: { account_id: @hosting.id }, as: :turbo_stream
    get bank_transactions_path(status: "matched")
    assert_select "##{row_id(plain)} .recon-actions .why", 0
  end

  test "memory OK is refused when the books no longer agree" do
    coded("ZOOM.US", account: @hosting, on: Date.new(2026, 9, 1), contact: "Zoom")
    fresh = line(-15, description: "ZOOM.US")
    post accept_suggestion_bank_transaction_path(fresh), params: { kind: "memory" }, as: :turbo_stream
    assert_response :unprocessable_entity
    assert_equal "unmatched", fresh.reload.status
  end

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
    assert_match(/Invoice INV-\d+ \$100\.00/, response.body)
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

  test "bank rules can be created from a line, carry several conditions, and be edited" do
    txn = line(-8, payee: "CLOUDFLARE")
    get new_bank_rule_path(bank_transaction_id: txn.id)
    assert_response :success
    assert_select "input[name='bank_rule[conditions_attributes][0][value]'][value=CLOUDFLARE]"
    assert_select "select[name='bank_rule[conditions_attributes][0][field]'] option[selected][value=text]"
    assert_select "input[name='bank_rule[match_all]'][value=true]"
    assert_select "template[data-nested-rows-target=template]"

    post bank_rules_path, params: { bank_rule: { name: "CF", amount_sign: "out", action_kind: "Expense", account_id: @hosting.id, auto_apply: "1", active: "1", match_all: "true",
      conditions_attributes: { "0" => { field: "text", operator: "contains", value: "cloudflare" }, "1" => { field: "amount", operator: "less_than", value: "50" } } } }
    assert_redirected_to bank_rules_path
    rule = @org.bank_rules.sole
    assert_equal 2, rule.conditions.count
    probe = ->(amount) { @org.bank_transactions.new(bank_account: @checking, posted_on: Date.current, amount: amount, payee: "CLOUDFLARE", description: "x") }
    assert rule.matches?(probe.(-8))
    assert_not rule.matches?(probe.(-80))

    get bank_rules_path
    assert_select "td", text: "CF"
    assert_select "td", text: /contains “cloudflare” and amount less than 50\.00/

    second = rule.conditions.last
    patch bank_rule_path(rule), params: { bank_rule: { name: "Cloudflare", match_all: "false", conditions_attributes: { "0" => { id: second.id, _destroy: "1" } } } }
    rule.reload
    assert_equal "Cloudflare", rule.name
    assert_equal 1, rule.conditions.count
    assert_not rule.match_all?

    patch bank_rule_path(rule), params: { bank_rule: { conditions_attributes: { "0" => { id: rule.conditions.sole.id, _destroy: "1" } } } }
    assert_response :unprocessable_entity
    assert_match(/at least one/, response.body)

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

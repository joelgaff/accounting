require "test_helper"

class Reconciliation::UpgradesTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @checking = create_bank_account(@org, name: "Checking")
    @savings  = create_bank_account(@org, name: "Savings", kind: "savings")
    @ar       = Plutus::Asset.create!(tenant: @org, name: "AR")
    @ap       = Plutus::Liability.create!(tenant: @org, name: "AP")
    @sales    = Plutus::Revenue.create!(tenant: @org, name: "Sales")
    @hosting  = Plutus::Expense.create!(tenant: @org, name: "Hosting")
  end

  def line(amount, bank: @checking, on: Date.current, description: "LINE", payee: "")
    @org.bank_transactions.create!(bank_account: bank, posted_on: on, amount: amount, description: description, payee: payee)
  end

  test "allocate splits a line across invoices and sweeps the rest into a deposit" do
    a = create_invoice(@org, client_name: "Acme", amount: 300, receivable: @ar, revenue: @sales)
    b = create_invoice(@org, client_name: "Bolt", amount: 200, receivable: @ar, revenue: @sales)
    txn = line(550)

    Reconciliation::Allocate.new(txn, allocations: [ { document_id: a.id, amount: "300" }, { document_id: b.id, amount: "200" } ], remainder: { account_id: @sales.id }).call
    txn.reload
    assert txn.matched?
    assert_equal 2, txn.payments.count
    assert a.reload.paid? && b.reload.paid?
    assert txn.document.deposit?
    assert_equal BigDecimal("50"), txn.document.total
    assert_equal BigDecimal("550"), @checking.balance
    assert_equal Plutus::DebitAmount.sum(:amount), Plutus::CreditAmount.sum(:amount)
  end

  test "a partial allocation leaves the line unmatched with a remainder, and over-allocation is refused" do
    a = create_invoice(@org, client_name: "Acme", amount: 300, receivable: @ar, revenue: @sales)
    txn = line(500)
    Reconciliation::Allocate.new(txn, allocations: [ { document_id: a.id, amount: "300" } ]).call
    txn.reload
    assert txn.unmatched?
    assert txn.partial?
    assert_equal BigDecimal("200"), txn.remaining
    assert_raises(Reconciliation::MatchDocument::Mismatch) do
      Reconciliation::Allocate.new(txn, allocations: [ { document_id: a.id, amount: "250" } ]).call
    end
    Reconciliation::Categorize.new(txn, account: @sales).call     # the rest
    assert txn.reload.matched?
    assert_equal BigDecimal("200"), txn.document.total
  end

  test "unmatch unwinds payments, removes reconcile-made documents, keeps hand-made ones, frees both transfer sides" do
    inv = create_invoice(@org, client_name: "Acme", amount: 100, receivable: @ar, revenue: @sales)
    t1  = line(100)
    Reconciliation::MatchDocument.new(t1, inv).call
    Reconciliation::Unmatch.new(t1).call
    assert t1.reload.unmatched?
    assert_equal 0, Payment.count
    assert_equal "open", inv.reload.status

    t2 = line(-30)
    Reconciliation::Categorize.new(t2, account: @hosting).call
    made = t2.reload.document
    Reconciliation::Unmatch.new(t2).call
    assert_not Document.exists?(made.id), "a document the reconcile page created goes away"
    assert_equal BigDecimal("0"), @hosting.balance

    exp = create_expense(@org, vendor: "DO", amount: 20, category: @hosting, bank_account: @checking)
    t3  = line(-20)
    Reconciliation::MatchDocument.new(t3, exp).call
    Reconciliation::Unmatch.new(t3).call
    assert Document.exists?(exp.id), "a document a person made only comes unlinked"
    assert_nil t3.reload.document
    assert_equal BigDecimal("20"), @hosting.balance

    out = line(-500); inn = line(500, bank: @savings)
    Reconciliation::CreateTransfer.new(out, other_bank_account: @savings).call
    Reconciliation::Unmatch.new(inn).call
    assert out.reload.unmatched?
    assert inn.reload.unmatched?
    assert_equal 0, @org.documents.transfers.count
  end

  test "suggester ranks exact amount, then date, then shared words; confident only on exact amount" do
    old   = create_invoice(@org, client_name: "Acme", amount: 500, receivable: @ar, revenue: @sales, date: Date.current - 20)
    fresh = create_invoice(@org, client_name: "Acme", amount: 500, receivable: @ar, revenue: @sales, date: Date.current - 1)
    near  = create_invoice(@org, client_name: "Bolt", amount: 510, receivable: @ar, revenue: @sales, date: Date.current)
    txn   = line(500, payee: "ACME CORP")

    cands = Reconciliation::Candidates.new(@org, [ txn ])
    ranked = Reconciliation::Suggester.new(@org, [ txn ], candidates: cands).for(txn)
    assert_equal [ fresh, old, near ], ranked.map(&:target)
    assert ranked.first.confident?
    assert_not ranked.last.confident?
  end

  test "suggester offers a mirror line as a transfer and a matching rule first" do
    out = line(-250, payee: "TRANSFER")
    inn = line(250, bank: @savings, on: Date.current + 1)
    cands = Reconciliation::Candidates.new(@org, [ out ])
    s = Reconciliation::Suggester.new(@org, [ out ], candidates: cands).top(out)
    assert_equal :transfer_pair, s.kind
    assert_equal inn, s.target

    rule = @org.bank_rules.create!(name: "Savings sweep", pattern: "transfer", action_kind: "Transfer", transfer_bank_account: @savings)
    s = Reconciliation::Suggester.new(@org, [ out ], candidates: cands).top(out)
    assert_equal :rule, s.kind
    assert_equal rule, s.target
  end

  test "apply_rules auto-applies flagged rules and only suggests the others" do
    @org.bank_rules.create!(name: "CF", pattern: "cloudflare", action_kind: "Expense", account: @hosting, auto_apply: true)
    @org.bank_rules.create!(name: "AWS", pattern: "amazon", action_kind: "Expense", account: @hosting)
    cf, aws, other = line(-8, payee: "CLOUDFLARE"), line(-40, payee: "AMAZON WEB"), line(-1, payee: "?")
    outcome = Reconciliation::ApplyRules.new(@org, [ cf, aws, other ]).call
    assert_equal 1, outcome.applied
    assert_equal 1, outcome.suggested
    assert cf.reload.matched?
    assert aws.reload.unmatched?
    assert_equal "AWS", aws.bank_rule.name
    assert_nil other.reload.bank_rule
  end

  test "statement import keeps payee and runs the rules" do
    @org.bank_rules.create!(name: "CF", pattern: "cloudflare", action_kind: "Expense", account: @hosting, auto_apply: true)
    csv = "*Date,*Amount,Payee,Description\n15 Jul 2026,-8.00,Cloudflare,Hosting\n16 Jul 2026,250.00,Acme,INV 1\n"
    result = Imports::BankStatementService.new(csv, bank_account: @checking, organization: @org).call
    assert_equal 2, result.imported
    assert_equal 1, result.rules_applied
    assert_equal "Cloudflare", @org.bank_transactions.find_by(amount: -8).payee
    assert @org.bank_transactions.find_by(amount: -8).matched?
  end

  test "summary reports ledger vs statement per account with unmatched totals" do
    create_expense(@org, vendor: "DO", amount: 20, category: @hosting, bank_account: @checking)
    @checking.update!(statement_balance: -25, statement_balance_at: Time.current)
    line(-5)
    rows = Reconciliation::Summary.new(@org).rows
    row = rows.find { |r| r.bank_account == @checking }
    assert_equal BigDecimal("-20"), row.ledger_balance
    assert_equal BigDecimal("-5"),  row.difference
    assert_equal 1, row.unmatched_count
    assert_equal BigDecimal("-5"), row.unmatched_total
  end
end

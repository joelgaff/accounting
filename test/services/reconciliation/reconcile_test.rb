require "test_helper"

class Reconciliation::ReconcileTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @checking = create_bank_account(@org, name: "Checking")
    @savings  = create_bank_account(@org, name: "Savings", kind: "savings")
    @ar       = Plutus::Asset.create!(tenant: @org, name: "AR")
    @ap       = Plutus::Liability.create!(tenant: @org, name: "AP")
    @sales    = Plutus::Revenue.create!(tenant: @org, name: "Sales")
    @hosting  = Plutus::Expense.create!(tenant: @org, name: "Hosting")
    @taxl     = Plutus::Liability.create!(tenant: @org, name: "Tax")
  end

  def line(amount, bank: @checking, on: Date.current, description: "LINE")
    @org.bank_transactions.create!(bank_account: bank, posted_on: on, amount: amount, description: description)
  end

  test "tax-inclusive split lands on the gross to the cent" do
    [ [ "108.75", "0.0875" ], [ "113.00", "0.13" ], [ "7.50", "0.075" ], [ "99.99", "0.10" ], [ "20.00", "0" ] ].each do |gross, rate|
      net, tax = Reconciliation::TaxInclusive.split(BigDecimal(gross), BigDecimal(rate))
      assert_equal BigDecimal(gross), net + (net * BigDecimal(rate)).round(2), "#{gross} @ #{rate}"
      assert_equal BigDecimal(gross), net + tax
    end
  end

  test "matching a deposit to an invoice creates a payment and marks the line" do
    inv = create_invoice(@org, client_name: "Acme", amount: 500, receivable: @ar, revenue: @sales)
    txn = line(500)
    Reconciliation::MatchDocument.new(txn, inv).call
    assert inv.reload.paid?
    assert_equal "matched", txn.reload.status
    assert_equal inv, txn.matched_document
    assert_equal BigDecimal("500"), @checking.balance
  end

  test "matching an existing expense checks direction, bank and amount" do
    exp = create_expense(@org, vendor: "DO", amount: 20, category: @hosting, bank_account: @checking)
    assert_raises(Reconciliation::MatchDocument::Mismatch) { Reconciliation::MatchDocument.new(line(20), exp).call }
    assert_raises(Reconciliation::MatchDocument::Mismatch) { Reconciliation::MatchDocument.new(line(-25), exp).call }
    txn = line(-20)
    Reconciliation::MatchDocument.new(txn, exp).call
    assert_equal exp, txn.reload.matched
    assert_equal 0, Payment.count
  end

  test "categorize builds an expense for money out and a deposit for money in, with tax and a contact" do
    rate = @org.tax_rates.create!(name: "Tax 8.75%", rate: 0.0875, liability_account: @taxl)
    out  = line(-108.75, description: "CLOUDFLARE")
    Reconciliation::Categorize.new(out, account: @hosting, tax_rate: rate, contact_name: "Cloudflare").call
    exp = out.reload.matched
    assert exp.expense?
    assert_equal BigDecimal("108.75"), exp.total
    assert_equal "Cloudflare", exp.contact.name
    assert_equal "vendor", exp.contact.kind
    assert_equal "reconcile", exp.source
    assert_equal BigDecimal("-108.75"), @checking.balance

    inn = line(250, description: "FAIR SPONSOR")
    Reconciliation::Categorize.new(inn, account: @sales, contact_name: "cloudflare").call   # same contact, other side
    dep = inn.reload.matched
    assert dep.deposit?
    assert_equal exp.contact, dep.contact
    assert_equal "both", exp.contact.reload.kind
    assert_equal Plutus::DebitAmount.sum(:amount), Plutus::CreditAmount.sum(:amount)
  end

  test "a transfer from one line links the mirror line within three days, nearest first" do
    out   = line(-1000, on: Date.new(2026, 9, 1))
    near  = line(1000, bank: @savings, on: Date.new(2026, 9, 2))
    far   = line(1000, bank: @savings, on: Date.new(2026, 9, 3))
    late  = line(1000, bank: @savings, on: Date.new(2026, 9, 9))

    result = Reconciliation::CreateTransfer.new(out, other_bank_account: @savings).call
    doc = out.reload.matched
    assert doc.transfer?
    assert_equal @checking, doc.transfer.from_bank_account
    assert_equal @savings,  doc.transfer.to_bank_account
    assert_equal near, result.sibling
    assert_equal doc, near.reload.matched
    assert far.reload.unmatched?
    assert late.reload.unmatched?
    assert_equal BigDecimal("-1000"), @checking.balance
    assert_equal BigDecimal("1000"),  @savings.balance
  end

  test "a transfer with no mirror line is single-sided until the other statement arrives" do
    out = line(-300)
    Reconciliation::CreateTransfer.new(out, other_bank_account: @savings).call
    doc = out.reload.matched
    assert doc.transfer.awaiting_side?(@savings)

    later = line(300, bank: @savings, on: Date.current + 1)
    cands = Reconciliation::Candidates.new(@org, [ later ]).for(later)
    assert_equal [ doc ], cands.transfers
    Reconciliation::MatchDocument.new(later, doc).call
    assert_not doc.transfer.reload.awaiting_side?(@savings)
  end

  test "candidates offer settleable documents within 5%, unlinked direct documents, and open transfers" do
    inv  = create_invoice(@org, client_name: "Acme", amount: 100, receivable: @ar, revenue: @sales)
    bill = create_bill(@org, vendor: "AWS", amount: 40, category: @hosting, payable: @ap)
    exp  = create_expense(@org, vendor: "DO", amount: 20, category: @hosting, bank_account: @checking)
    dep_line, wd_line, exp_line = line(103), line(-40), line(-20)

    c = Reconciliation::Candidates.new(@org, [ dep_line, wd_line, exp_line ])
    assert_equal [ inv ],  c.for(dep_line).documents
    assert_equal [ bill ], c.for(wd_line).documents
    assert_equal [ exp ],  c.for(exp_line).documents
    assert_not c.for(line(-500)).any?
  end
end

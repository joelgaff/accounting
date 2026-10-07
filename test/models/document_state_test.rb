require "test_helper"

class DocumentStateTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @ar    = Plutus::Asset.create!(tenant: @org, name: "AR")
    @sales = Plutus::Revenue.create!(tenant: @org, name: "Sales")
  end

  test "a document is draft or approved, nothing else, and approved unless told otherwise" do
    doc = create_invoice(@org, client_name: "Acme", amount: 10, receivable: @ar, revenue: @sales)
    assert_equal "approved", doc.state
    assert doc.approved?
    assert_not doc.draft?

    doc.state = "bogus"
    assert_not doc.valid?
    assert_includes doc.errors[:state].join, "not included"
  end

  test "a draft posts nothing until it is approved, and then exactly once" do
    doc = create_invoice(@org, client_name: "Acme", amount: 10, receivable: @ar, revenue: @sales, state: "draft")
    assert doc.draft?
    assert_equal 0, doc.entries.count

    doc.approve!
    assert doc.reload.approved?
    assert_equal 1, doc.entries.count
    assert_equal BigDecimal("10"), @ar.balance
    assert_equal "approved", doc.events.last.action

    assert_raises(ActiveRecord::RecordInvalid) { doc.approve! }
    assert_equal 1, doc.entries.count
  end

  test "editing a draft keeps it unposted" do
    doc = create_invoice(@org, client_name: "Acme", amount: 10, receivable: @ar, revenue: @sales, state: "draft")
    doc.update_and_repost!(reference: "quote 7", line_items_attributes: [ { id: doc.line_items.first.id, unit_amount: 25 } ])
    assert_equal BigDecimal("25"), doc.reload.total
    assert_equal 0, doc.entries.count
    assert doc.draft?
  end

  test "status says draft before anything the type would say" do
    ap  = Plutus::Liability.create!(tenant: @org, name: "AP")
    exp = Plutus::Expense.create!(tenant: @org, name: "Hosting")
    inv  = create_invoice(@org, client_name: "Acme", amount: 10, receivable: @ar, revenue: @sales, state: "draft", due_date: Date.current - 5)
    bill = create_bill(@org, vendor: "AWS", amount: 10, category: exp, payable: ap, state: "draft")
    assert_equal "draft", inv.status
    assert_equal "draft", bill.status
    inv.approve!
    assert_equal "overdue", inv.status
  end

  test "drafts stay out of everything that counts money" do
    bank = create_bank_account(@org, name: "Bank")
    ap   = Plutus::Liability.create!(tenant: @org, name: "AP")
    exp  = Plutus::Expense.create!(tenant: @org, name: "Hosting")
    @org.settings.update!(payable_account: ap)
    draft_inv  = create_invoice(@org, client_name: "Acme", amount: 300, receivable: @ar, revenue: @sales, state: "draft")
    real_inv   = create_invoice(@org, client_name: "Acme", amount: 100, receivable: @ar, revenue: @sales)
    draft_bill = create_bill(@org, vendor: "AWS", amount: 45, category: exp, payable: ap, state: "draft")
    voided     = create_invoice(@org, client_name: "Acme", amount: 7, receivable: @ar, revenue: @sales).tap(&:void!)

    assert_equal [ real_inv ], @org.documents.posted.invoices.to_a
    assert_not_includes @org.documents.posted, voided

    assert_equal BigDecimal("100"), Reports::AccountsReceivableAging.new(organization: @org).grand_total
    category = @org.tracking_categories.create!(name: "Class")
    assert_equal BigDecimal("100"), Reports::ProfitAndLossByTracking.new(organization: @org, category: category).total_revenue
    assert_equal BigDecimal("0"),   Reports::AccountsPayableAging.new(organization: @org).grand_total

    line  = @org.bank_transactions.create!(bank_account: bank, posted_on: Date.current, amount: 300, payee: "Acme", description: "ACH")
    cands = Reconciliation::Candidates.new(@org, [ line ])
    assert_not_includes cands.for(line).documents, draft_inv
    assert_not_includes cands.pool_for(line), draft_inv

    payment = Payment.new(organization: @org, document: draft_inv, bank_account: bank, amount: 300, paid_on: Date.current)
    assert_not payment.valid?
    assert_includes payment.errors[:document].join, "draft"
    assert draft_bill.deletable?
  end

  test "a draft can't be voided, there is nothing to unwind" do
    doc = create_invoice(@org, client_name: "Acme", amount: 10, receivable: @ar, revenue: @sales, state: "draft")
    assert_raises(ActiveRecord::RecordInvalid) { doc.void! }
    assert_not doc.reload.voided?
    assert doc.draft?
  end

  test "an approved document with nothing against it can go back to draft" do
    doc = create_invoice(@org, client_name: "Acme", amount: 10, receivable: @ar, revenue: @sales)
    doc.unapprove!
    assert doc.reload.draft?
    assert_equal 0, doc.entries.count
    assert_equal BigDecimal("0"), @ar.balance
  end
end

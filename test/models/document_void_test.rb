require "test_helper"

class DocumentVoidTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @bank    = create_bank_account(@org, name: "Bank")
    @ar      = Plutus::Asset.create!(tenant: @org, name: "AR")
    @sales   = Plutus::Revenue.create!(tenant: @org, name: "Sales")
    @hosting = Plutus::Expense.create!(tenant: @org, name: "Hosting")
  end

  test "void removes postings, cascades to payments and releases bank lines" do
    inv = create_invoice(@org, client_name: "Acme", amount: 500, receivable: @ar, revenue: @sales)
    txn = @org.bank_transactions.create!(bank_account: @bank, posted_on: Date.current, amount: 500, description: "ACME")
    Reconciliation::MatchDocument.new(txn, inv).call
    assert_equal 1, inv.payments.count
    assert_equal({ payments: 1, paid: BigDecimal("500"), bank_lines: 1 }, inv.void_consequences)

    inv.void!
    inv.reload
    assert inv.voided?
    assert_equal "voided", inv.status
    assert_equal 0, inv.payments.count
    assert_equal 0, Plutus::Entry.count
    assert_equal BigDecimal("0"), @ar.balance
    assert_equal BigDecimal("0"), @bank.balance
    assert_equal BigDecimal("0"), inv.balance_due
    assert txn.reload.unmatched?
    assert_empty txn.payments
    assert Invoice.exists?(inv.documentable_id), "the record stays for the audit trail"
    assert_not_includes @org.documents.live, inv
    assert_includes @org.documents.voided, inv
  end

  test "voiding a reconcile-created expense returns its line to the queue" do
    txn = @org.bank_transactions.create!(bank_account: @bank, posted_on: Date.current, amount: -30, description: "HOST")
    Reconciliation::Categorize.new(txn, account: @hosting).call
    exp = txn.reload.document
    exp.void!
    assert txn.reload.unmatched?
    assert_equal BigDecimal("0"), @hosting.balance
  end

  test "voiding a transfer releases both sides" do
    savings = create_bank_account(@org, name: "Savings", kind: "savings")
    out = @org.bank_transactions.create!(bank_account: @bank, posted_on: Date.current, amount: -100, description: "TFR")
    inn = @org.bank_transactions.create!(bank_account: savings, posted_on: Date.current, amount: 100, description: "TFR")
    Reconciliation::CreateTransfer.new(out, other_bank_account: savings).call
    out.reload.document.void!
    assert out.reload.unmatched?
    assert inn.reload.unmatched?
    assert_equal BigDecimal("0"), savings.balance
  end

  test "a voided document refuses edits and a second void" do
    inv = create_invoice(@org, client_name: "Acme", amount: 500, receivable: @ar, revenue: @sales)
    inv.void!
    assert_raises(ActiveRecord::RecordInvalid) { inv.update_and_repost!(reference: "x") }
    assert_raises(ActiveRecord::RecordInvalid) { inv.void! }
  end

  test "update_and_repost! replaces lines and posts once at the new total" do
    inv  = create_invoice(@org, client_name: "Acme", amount: 500, receivable: @ar, revenue: @sales)
    line = inv.line_items.sole
    inv.update_and_repost!(reference: "R-1", line_items_attributes: [
      { id: line.id, _destroy: "1" },
      { description: "Consulting", quantity: 2, unit_amount: 300, account_id: @sales.id }
    ])
    inv.reload
    assert_equal "R-1", inv.reference
    assert_equal BigDecimal("600"), inv.total
    assert_equal 1, inv.line_items.count
    assert_equal 1, inv.entries.count
    assert_equal BigDecimal("600"), @ar.balance
    assert_equal Plutus::DebitAmount.sum(:amount), Plutus::CreditAmount.sum(:amount)
  end

  test "an edit can't drop the total below what has been paid, or change a bank-matched amount" do
    inv = create_invoice(@org, client_name: "Acme", amount: 500, receivable: @ar, revenue: @sales)
    inv.payments.create!(organization: @org, amount: 400, paid_on: Date.current, bank_account: @bank)
    line = inv.line_items.sole
    err = assert_raises(ActiveRecord::RecordInvalid) do
      inv.update_and_repost!(line_items_attributes: [ { id: line.id, unit_amount: 100 } ])
    end
    assert_match(/already paid/, err.message)
    assert_equal BigDecimal("500"), inv.reload.total

    txn = @org.bank_transactions.create!(bank_account: @bank, posted_on: Date.current, amount: -30, description: "HOST")
    Reconciliation::Categorize.new(txn, account: @hosting).call
    exp = txn.reload.document
    err = assert_raises(ActiveRecord::RecordInvalid) do
      exp.update_and_repost!(line_items_attributes: [ { id: exp.line_items.sole.id, unit_amount: 31 } ])
    end
    assert_match(/unmatch it first/, err.message)
  end

  test "Payment#unwind! resets its posting and frees its bank line" do
    inv = create_invoice(@org, client_name: "Acme", amount: 500, receivable: @ar, revenue: @sales)
    txn = @org.bank_transactions.create!(bank_account: @bank, posted_on: Date.current, amount: 500, description: "ACME")
    Reconciliation::MatchDocument.new(txn, inv).call
    inv.payments.sole.unwind!
    assert_equal BigDecimal("500"), @ar.balance
    assert_equal BigDecimal("0"),   @bank.balance
    assert txn.reload.unmatched?
    assert_equal "open", inv.reload.status
  end
end

require "test_helper"

class DocumentTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @bank    = create_bank_account(@org, name: "Bank")
    @ar      = Plutus::Asset.create!(tenant: @org, name: "AR")
    @ap      = Plutus::Liability.create!(tenant: @org, name: "AP")
    @sales   = Plutus::Revenue.create!(tenant: @org, name: "Sales")
    @hosting = Plutus::Expense.create!(tenant: @org, name: "Hosting")
  end

  test "each type posts a balanced entry attributed to the document" do
    inv  = create_invoice(@org, client_name: "Acme", amount: 500, receivable: @ar, revenue: @sales)
    bill = create_bill(@org, vendor: "AWS", amount: 45, category: @hosting, payable: @ap)
    exp  = create_expense(@org, vendor: "DO", amount: 20, category: @hosting, bank_account: @bank)
    je   = @org.documents.create!(date: Date.current, documentable: JournalEntry.new(
      narrative: "Adjust", lines_attributes: [ { account_id: @hosting.id, debit_amount: 5 }, { account_id: @bank.account.id, credit_amount: 5 } ]))

    [ inv, bill, exp, je ].each do |doc|
      assert_equal 1, doc.entries.count, "#{doc.label} should post once"
      assert_equal doc, doc.entries.sole.commercial_document
    end
    assert_equal Plutus::DebitAmount.sum(:amount), Plutus::CreditAmount.sum(:amount)
    assert_equal BigDecimal("500"), @ar.balance
    assert_equal BigDecimal("45"),  @ap.balance
    assert_equal BigDecimal("-25"), @bank.balance
    assert_equal BigDecimal("70"),  @hosting.balance
  end

  test "totals sync from line items, and from journal lines" do
    inv = create_invoice(@org, client_name: "Acme", amount: 100, receivable: @ar, revenue: @sales)
    assert_equal [ BigDecimal("100"), BigDecimal("0"), BigDecimal("100") ], [ inv.subtotal, inv.tax_amount, inv.total ]

    je = @org.documents.create!(date: Date.current, documentable: JournalEntry.new(
      narrative: "x", lines_attributes: [ { account_id: @hosting.id, debit_amount: 150 }, { account_id: @bank.account.id, credit_amount: 150 } ]))
    assert_equal BigDecimal("150"), je.total
  end

  test "type-level validation errors block the document" do
    doc = @org.documents.build(date: Date.current, documentable: Invoice.new(receivable_account: @ar),
                               line_items_attributes: [ { description: "x", quantity: 1, unit_amount: 10, account_id: @sales.id } ])
    assert_not doc.valid?
    assert doc.errors.full_messages.any? { |m| m =~ /client name/i }, doc.errors.full_messages.inspect
  end

  test "a contact's name flows onto the invoice and the bill" do
    contact = @org.contacts.create!(name: "Big Client", kind: "both")
    inv  = create_invoice(@org, contact: contact, amount: 10, receivable: @ar, revenue: @sales)
    bill = create_bill(@org, contact: contact, amount: 10, category: @hosting, payable: @ap)
    assert_equal "Big Client", inv.invoice.client_name
    assert_equal "Big Client", bill.bill.vendor
    assert_equal "Big Client", inv.counterparty
  end

  test "rejects a document with no line items or a zero total" do
    doc = @org.documents.build(date: Date.current, documentable: Invoice.new(client_name: "x", due_date: Date.current, receivable_account: @ar))
    assert_not doc.valid?
    assert_includes doc.errors[:base].join, "line item"
  end

  test "only invoices and bills take payments" do
    exp = create_expense(@org, vendor: "DO", amount: 20, category: @hosting, bank_account: @bank)
    p = exp.payments.build(organization: @org, amount: 20, paid_on: Date.current, bank_account: @bank)
    assert_not p.valid?
    assert_includes p.errors[:document].join, "cannot take payments"
    assert_not exp.settleable?
    assert create_invoice(@org, client_name: "A", amount: 1, receivable: @ar, revenue: @sales).settleable?
  end

  test "repost_to_ledger! leaves exactly one entry and the same balances" do
    inv = create_invoice(@org, client_name: "Acme", amount: 500, receivable: @ar, revenue: @sales)
    inv.repost_to_ledger!
    assert_equal 1, inv.entries.count
    assert_equal BigDecimal("500"), @ar.balance
  end

  test "destroying a document removes its type row, lines and posting" do
    inv = create_invoice(@org, client_name: "Acme", amount: 500, receivable: @ar, revenue: @sales)
    type_id = inv.documentable_id
    Ledger.reset_for(inv)
    inv.destroy!
    assert_not Invoice.exists?(type_id)
    assert_equal 0, LineItem.count
    assert_equal 0, Plutus::Entry.count
  end

  test "outstanding_between finds documents by balance due" do
    inv = create_invoice(@org, client_name: "Acme", amount: 500, receivable: @ar, revenue: @sales)
    inv.payments.create!(organization: @org, amount: 200, paid_on: Date.current, bank_account: @bank)
    assert_includes @org.documents.invoices.outstanding_between(290, 310), inv
    assert_not_includes @org.documents.invoices.outstanding_between(490, 510), inv
  end

  test "label and scopes come from the delegated type" do
    inv = create_invoice(@org, client_name: "Acme", amount: 1, receivable: @ar, revenue: @sales)
    assert_equal "Invoice ##{inv.id}", inv.label
    assert inv.invoice?
    assert_equal [ inv ], @org.documents.invoices.to_a
    assert_empty @org.documents.bills
  end
end

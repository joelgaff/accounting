require "test_helper"

class InvoiceNumberingTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @ar    = Plutus::Asset.create!(tenant: @org, name: "AR")
    @sales = Plutus::Revenue.create!(tenant: @org, name: "Sales")
  end

  test "new invoices are numbered from INV-0001 and continue after the highest number in the run" do
    first = create_invoice(@org, client_name: "A", amount: 10, receivable: @ar, revenue: @sales)
    assert_equal "INV-0001", first.invoice.number
    assert_equal "Invoice INV-0001", first.label

    imported = @org.documents.create!(date: Date.current, documentable: Invoice.new(client_name: "X", due_date: Date.current, receivable_account: @ar, number: "INV-2378", xero_invoice_number: "INV-2378"),
      line_items_attributes: [ { description: "x", quantity: 1, unit_amount: 5, account_id: @sales.id } ])
    assert_equal "INV-2378", imported.invoice.number
    nxt = create_invoice(@org, client_name: "B", amount: 10, receivable: @ar, revenue: @sales)
    assert_equal "INV-2379", nxt.invoice.number
  end

  test "a number typed on the form is kept, and a duplicate is refused" do
    create_invoice(@org, client_name: "A", amount: 10, receivable: @ar, revenue: @sales, documentable_attributes: { number: "EE-100" })
    assert_equal "EE-100", Invoice.last.number
    dup = @org.documents.build(date: Date.current, documentable: Invoice.new(client_name: "B", due_date: Date.current, receivable_account: @ar, number: "EE-100"))
    dup.line_items.build(description: "x", quantity: 1, unit_amount: 1, account: @sales)
    assert_not dup.save
    assert_match(/already used/, dup.errors.full_messages.join)
    assert_equal "EE-101", Invoice.next_number(@org)
  end

  test "bills show the vendor's number when there is one" do
    ap   = Plutus::Liability.create!(tenant: @org, name: "AP")
    cost = Plutus::Expense.create!(tenant: @org, name: "Cost")
    numbered   = create_bill(@org, vendor: "V", amount: 10, category: cost, payable: ap, documentable_attributes: { number: "79738R" })
    unnumbered = create_bill(@org, vendor: "V", amount: 10, category: cost, payable: ap)
    assert_equal "Bill 79738R", numbered.label
    assert_equal "Bill ##{unnumbered.id}", unnumbered.label
  end
end

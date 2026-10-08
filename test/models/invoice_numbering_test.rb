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
  end

  test "numbers under another prefix never steer the sequence" do
    create_invoice(@org, client_name: "A", amount: 10, receivable: @ar, revenue: @sales, documentable_attributes: { number: "V1920067" })
    create_invoice(@org, client_name: "B", amount: 10, receivable: @ar, revenue: @sales, documentable_attributes: { number: "INV-0042" })
    assert_equal "INV-0043", Invoice.next_number(@org)
  end

  test "settings own the prefix and the next number, and saving an invoice advances it" do
    settings = @org.settings
    assert_equal "INV-", settings.invoice_prefix
    assert_nil settings.invoice_next_number, "nothing set yet: the sequence follows the invoices that exist"

    settings.update!(invoice_prefix: "EE-", invoice_next_number: 500)
    assert_equal "EE-0500", Invoice.next_number(@org)
    saved = create_invoice(@org, client_name: "A", amount: 10, receivable: @ar, revenue: @sales)
    assert_equal "EE-0500", saved.invoice.number
    assert_equal 501, settings.reload.invoice_next_number

    create_invoice(@org, client_name: "B", amount: 10, receivable: @ar, revenue: @sales, documentable_attributes: { number: "EE-0700" })
    assert_equal 701, settings.reload.invoice_next_number, "a higher number typed by hand moves the sequence up"
    create_invoice(@org, client_name: "C", amount: 10, receivable: @ar, revenue: @sales, documentable_attributes: { number: "EE-0010" })
    assert_equal 701, settings.reload.invoice_next_number, "a lower one never moves it down"
    create_invoice(@org, client_name: "D", amount: 10, receivable: @ar, revenue: @sales, documentable_attributes: { number: "OLD-9999" })
    assert_equal 701, settings.reload.invoice_next_number, "another prefix is none of its business"

    settings.update!(invoice_prefix: "")
    assert_equal "0701", Invoice.next_number(@org)
  end

  test "the sequence steps over numbers already in the books" do
    create_invoice(@org, client_name: "Old", amount: 10, receivable: @ar, revenue: @sales, documentable_attributes: { number: "INV-2378" })
    settings = @org.settings
    settings.update!(invoice_next_number: 2377)
    assert_equal "INV-2377", Invoice.next_number(@org), "the gap below is free"

    filled = create_invoice(@org, client_name: "A", amount: 10, receivable: @ar, revenue: @sales)
    assert_equal "INV-2377", filled.invoice.number
    assert_equal 2379, settings.reload.invoice_next_number, "2378 is taken, so the counter lands past it"
    assert_equal "INV-2379", Invoice.next_number(@org)

    settings.update!(invoice_next_number: 2378)
    assert_equal "INV-2379", Invoice.next_number(@org), "a counter set on a used number offers the next free one"
  end

  test "the next number must be a whole number of one or more" do
    settings = @org.settings
    assert_not settings.update(invoice_next_number: 0)
    assert_not settings.update(invoice_next_number: -3)
    assert settings.update(invoice_next_number: nil)
    assert settings.update(invoice_next_number: 2380)
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

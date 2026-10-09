require "test_helper"

# Copying an invoice or bill prefills a new one with what repeats (who, the
# lines, their tracking) and nothing of what belonged to the original alone
# (number, dates, state, sent mark, payments, attachments, reference, memo).
class DocumentCopyTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @ar      = Plutus::Asset.create!(tenant: @org, name: "AR", code: "1200")
    @ap      = Plutus::Liability.create!(tenant: @org, name: "AP", code: "2000")
    @sales   = Plutus::Revenue.create!(tenant: @org, name: "Sales", code: "200")
    @hosting = Plutus::Expense.create!(tenant: @org, name: "Hosting", code: "400")
    @bank    = create_bank_account(@org, name: "Checking")
    @gst     = @org.tax_rates.create!(name: "GST", rate: 0.1, liability_account: Plutus::Liability.create!(tenant: @org, name: "GST owed", code: "2200"))
    @klass   = @org.tracking_categories.create!(name: "Class", options_attributes: [ { name: "Summit Races" } ])
    @org.settings.update!(receivable_account: @ar, payable_account: @ap)
    @customer = @org.contacts.create!(name: "Acme", kind: "customer")
  end

  test "a copied invoice carries the customer, the lines and their tracking, and keeps the payment terms" do
    original = create_invoice(@org, contact: @customer, amount: 500, receivable: @ar, revenue: @sales, tax_rate: @gst,
                              date: Date.new(2026, 1, 10), due_date: Date.new(2026, 1, 24),   # net 14
                              reference: "PO 4471", memo: "January retainer")
    original.line_items.first.update!(tracking_option_ids: [ @klass.options.first.id ])
    original.line_items.create!(description: "Travel", quantity: 2, unit_amount: 30, account: @sales)
    original.payments.create!(organization: @org, amount: 100, paid_on: Date.current, bank_account: @bank)
    original.invoice.mark_sent!

    copy = @org.documents.build(date: Date.current, documentable: Invoice.new(number: "INV-0099", receivable_account: @ar))
    copy.state = "draft"
    copy.copy_from(original)

    assert_equal @customer, copy.contact
    assert_equal "Acme", copy.invoice.client_name
    assert_equal Date.current, copy.date
    assert_equal Date.current + 14, copy.invoice.due_date, "the gap between issue and due comes across, not the dates"

    assert_equal [ "Services rendered", "Travel" ], copy.line_items.map(&:description)
    travel = copy.line_items.last
    assert_equal 2, travel.quantity
    assert_equal 30, travel.unit_amount
    assert_equal @sales, travel.account
    assert_equal @gst, copy.line_items.first.tax_rate
    assert_equal [ @klass.options.first.id ], copy.line_items.first.tracking_option_ids
    assert copy.line_items.all?(&:new_record?)

    assert_equal "INV-0099", copy.invoice.number, "the copy keeps the number it was given"
    assert copy.draft?
    assert_nil copy.invoice.sent_at
    assert_nil copy.reference
    assert_nil copy.memo
    assert_empty copy.payments
    assert_equal "manual", copy.source
    assert_equal original.id, copy.copied_from_id

    assert copy.save
    assert_equal 560, copy.subtotal
    assert_equal 0, copy.entries.count, "a draft; nothing posted"
    assert_equal original.reload.total, original.total, "the original is untouched"
    assert_equal 1, original.payments.count
  end

  test "a copied bill carries the vendor and lines" do
    aws      = @org.contacts.create!(name: "AWS", kind: "vendor")
    original = create_bill(@org, contact: aws, vendor: "AWS", amount: 45, category: @hosting, payable: @ap, date: Date.new(2026, 1, 1))
    copy = @org.documents.build(date: Date.current, documentable: Bill.new(payable_account: @ap))
    copy.copy_from(original)
    assert_equal "AWS", copy.bill.vendor
    assert_equal aws, copy.contact
    assert_equal Date.current, copy.date
    assert_equal [ 45 ], copy.line_items.map(&:unit_amount)
    assert_equal @hosting, copy.line_items.first.account
  end
end

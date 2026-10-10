require "test_helper"

# An invoice line can record the billable expense it rebills. That link is
# what "billed" means: an expense is billed while a live invoice carries a
# line for it, draft or approved, and free again when none does.
class LineItemRebillsTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @ar      = Plutus::Asset.create!(tenant: @org, name: "AR", code: "1200")
    @ap      = Plutus::Liability.create!(tenant: @org, name: "AP", code: "2000")
    @sales   = Plutus::Revenue.create!(tenant: @org, name: "Sales", code: "4100")
    @travel  = Plutus::Expense.create!(tenant: @org, name: "Travel", code: "6812")
    @bank    = create_bank_account(@org, name: "Checking")
    @org.settings.update!(receivable_account: @ar, payable_account: @ap, bank_account: @bank)
    @northwind = @org.contacts.create!(name: "Northwind", kind: "customer")
    @ticket    = create_expense(@org, vendor: "Delta", amount: 500, category: @travel, bank_account: @bank, billable_to: @northwind)
  end

  def invoice_rebilling(ticket, state: "approved")
    create_invoice(@org, contact: @northwind, amount: 1, receivable: @ar, revenue: @sales, state: state).tap do |inv|
      inv.line_items.first.update!(unit_amount: 500, rebills: ticket)
    end
  end

  test "a line on an invoice rebills a flagged cost; the cost then knows the invoice" do
    assert_not @ticket.billed?
    assert_includes @org.documents.billable_to(@northwind).unbilled, @ticket

    inv = invoice_rebilling(@ticket, state: "draft")
    assert_equal @ticket, inv.line_items.first.rebills
    assert_equal inv, @ticket.reload.billed_on
    assert @ticket.billed?, "a draft holds the cost too"
    assert_not_includes @org.documents.billable_to(@northwind).unbilled, @ticket
  end

  test "voiding or deleting the invoice frees the cost; removing the line does too" do
    inv = invoice_rebilling(@ticket)
    inv.void!
    assert_nil @ticket.reload.billed_on

    again = invoice_rebilling(@ticket, state: "draft")
    assert_equal again, @ticket.reload.billed_on
    again.line_items.first.update!(rebills: nil)
    assert_nil @ticket.reload.billed_on

    once_more = invoice_rebilling(@ticket, state: "draft")
    once_more.destroy!
    assert_nil @ticket.reload.billed_on
  end

  test "a cost already on a live invoice can't be picked up again, but a voided one's can" do
    first  = invoice_rebilling(@ticket)
    second = create_invoice(@org, contact: @northwind, amount: 1, receivable: @ar, revenue: @sales, state: "draft")
    line   = second.line_items.first
    line.rebills = @ticket
    assert_not line.valid?
    assert_match(/already billed on #{Regexp.escape(first.label)}/, line.errors[:rebills].first)

    first.void!
    assert line.valid?
  end

  test "only a flagged purchase can be rebilled, only by an invoice line, only within the organisation" do
    plain = create_expense(@org, vendor: "Zoom", amount: 15, category: @travel, bank_account: @bank)
    inv   = create_invoice(@org, contact: @northwind, amount: 1, receivable: @ar, revenue: @sales, state: "draft")
    line  = inv.line_items.first
    line.rebills = plain
    assert_not line.valid?, "not flagged"

    other_inv = create_invoice(@org, contact: @northwind, amount: 9, receivable: @ar, revenue: @sales)
    line.rebills = other_inv
    assert_not line.valid?, "not a purchase"

    bill_line = create_bill(@org, vendor: "AWS", amount: 45, category: @travel, payable: @ap).line_items.first
    bill_line.rebills = @ticket
    assert_not bill_line.valid?, "only an invoice line rebills"

    stranger_org = Organization.create!(name: "Other")
    stranger     = stranger_org.contacts.create!(name: "Them", kind: "customer")
    s_bank       = create_bank_account(stranger_org, name: "Theirs")
    s_travel     = Plutus::Expense.create!(tenant: stranger_org, name: "Travel")
    theirs       = create_expense(stranger_org, vendor: "Delta", amount: 5, category: s_travel, bank_account: s_bank, billable_to: stranger)
    line.rebills = theirs
    assert_not line.valid?, "another organisation's cost"
  end

  test "copying an invoice drops the rebill links" do
    inv  = invoice_rebilling(@ticket)
    copy = @org.documents.build(date: Date.current, documentable: Invoice.new(receivable_account: @ar)).copy_from(inv)
    assert copy.line_items.none?(&:rebills)
  end
end

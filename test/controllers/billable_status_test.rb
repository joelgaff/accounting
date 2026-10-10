require "test_helper"

# Where unbilled costs show up besides the expense itself: the customer's
# page, with a total and a way to invoice them, and a chip on the lists.
class BillableStatusTest < ActionDispatch::IntegrationTest
  setup do
    @org = organizations(:one)
    sign_in_as_launchpad_user(@org)
    @ar     = Plutus::Asset.create!(tenant: @org, name: "AR", code: "1200")
    @ap     = Plutus::Liability.create!(tenant: @org, name: "AP", code: "2000")
    @sales  = Plutus::Revenue.create!(tenant: @org, name: "Sales", code: "4100")
    @travel = Plutus::Expense.create!(tenant: @org, name: "Travel", code: "6812")
    @bank   = create_bank_account(@org, name: "Checking")
    @org.settings.update!(receivable_account: @ar, payable_account: @ap, bank_account: @bank)
    @northwind = @org.contacts.create!(name: "Northwind", kind: "customer")
    @ticket = create_expense(@org, vendor: "Delta", amount: 500, category: @travel, bank_account: @bank, billable_to: @northwind, date: Date.new(2026, 3, 14))
    @hotel  = create_bill(@org, vendor: "Marriott", amount: 300, category: @travel, payable: @ap, billable_to: @northwind, date: Date.new(2026, 3, 15))
    @plain  = create_expense(@org, vendor: "Zoom", amount: 15, category: @travel, bank_account: @bank)
  end

  def row(doc) = "tr##{ActionView::RecordIdentifier.dom_id(doc)}"

  test "a customer's page lists what they have not been billed for yet, with the total" do
    get contact_path(@northwind)
    assert_select ".unbilled" do
      assert_select "h2", text: /Unbilled expenses.*\$800\.00/m
      assert_select row(@ticket)
      assert_select row(@hotel)
      assert_select row(@plain), 0
      assert_select "a[href=?]", new_invoice_path(contact_id: @northwind.id), text: "New invoice"
    end

    inv = create_invoice(@org, contact: @northwind, amount: 1, receivable: @ar, revenue: @sales, state: "draft")
    inv.line_items.first.update!(rebills: @ticket)
    get contact_path(@northwind)
    assert_select ".unbilled h2", text: /\$300\.00/
    assert_select ".unbilled #{row(@ticket)}", 0

    inv.line_items.create!(description: "Hotel", quantity: 1, unit_amount: 300, account: @sales, rebills: @hotel)
    get contact_path(@northwind)
    assert_select ".unbilled", 0, "nothing left to bill, no section"
  end

  test "the expense and bill lists have a Billable chip for what is flagged and not yet invoiced" do
    get expenses_path
    assert_select "nav.chips a[href=?]", expenses_path(status: "billable"), text: "Billable"
    get expenses_path(status: "billable")
    assert_select row(@ticket)
    assert_select row(@plain), 0

    get bills_path(status: "billable")
    assert_select row(@hotel)

    inv = create_invoice(@org, contact: @northwind, amount: 1, receivable: @ar, revenue: @sales, state: "draft")
    inv.line_items.first.update!(rebills: @ticket)
    get expenses_path(status: "billable")
    assert_select row(@ticket), 0, "billed now"
    get expenses_path
    assert_select row(@ticket), 1, "still an expense"
  end
end

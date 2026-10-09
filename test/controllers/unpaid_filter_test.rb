require "test_helper"

# "Unpaid" on the invoice and bill lists: everything approved that still owes
# money, oldest due first, so the chip answers "who owes me" and "what do I owe".
class UnpaidFilterTest < ActionDispatch::IntegrationTest
  setup do
    @org = organizations(:one)
    sign_in_as_launchpad_user(@org)
    @ar      = Plutus::Asset.create!(tenant: @org, name: "AR", code: "1200")
    @ap      = Plutus::Liability.create!(tenant: @org, name: "AP", code: "2000")
    @sales   = Plutus::Revenue.create!(tenant: @org, name: "Sales", code: "200")
    @hosting = Plutus::Expense.create!(tenant: @org, name: "Hosting", code: "400")
    @bank    = create_bank_account(@org, name: "Checking")
    @org.settings.update!(receivable_account: @ar, payable_account: @ap)
  end

  def row(doc) = "tr##{ActionView::RecordIdentifier.dom_id(doc)}"

  test "unpaid invoices are the open, partial and overdue ones, oldest due first" do
    overdue = create_invoice(@org, client_name: "Late", amount: 100, receivable: @ar, revenue: @sales, date: Date.current - 60, due_date: Date.current - 30)
    open    = create_invoice(@org, client_name: "Soon", amount: 100, receivable: @ar, revenue: @sales, date: Date.current, due_date: Date.current + 30)
    partial = create_invoice(@org, client_name: "Half", amount: 100, receivable: @ar, revenue: @sales, date: Date.current - 10, due_date: Date.current + 10)
    partial.payments.create!(organization: @org, amount: 40, paid_on: Date.current, bank_account: @bank)
    paid    = create_invoice(@org, client_name: "Done", amount: 100, receivable: @ar, revenue: @sales, date: Date.current - 20, due_date: Date.current - 5)
    paid.payments.create!(organization: @org, amount: 100, paid_on: Date.current, bank_account: @bank)
    draft   = create_invoice(@org, client_name: "Maybe", amount: 100, receivable: @ar, revenue: @sales, state: "draft")
    voided  = create_invoice(@org, client_name: "Gone", amount: 100, receivable: @ar, revenue: @sales)
    voided.void!

    get invoices_path
    assert_select "nav.chips a", text: "Unpaid"

    get invoices_path(status: "unpaid")
    assert_select "nav.chips a[aria-current=page]", text: "Unpaid"
    [ overdue, partial, open ].each { |d| assert_select row(d), 1 }
    [ paid, draft, voided ].each { |d| assert_select row(d), 0 }
    ids = css_select("tbody tr").map { |tr| tr["id"] }
    assert_equal [ overdue, partial, open ].map { |d| ActionView::RecordIdentifier.dom_id(d) }, ids, "oldest due first"
  end

  test "unpaid bills are the ones still owed, oldest first" do
    old_bill = create_bill(@org, vendor: "AWS", amount: 45, category: @hosting, payable: @ap, date: Date.current - 40)
    new_bill = create_bill(@org, vendor: "Zoom", amount: 15, category: @hosting, payable: @ap, date: Date.current - 2)
    settled  = create_bill(@org, vendor: "Gusto", amount: 90, category: @hosting, payable: @ap, date: Date.current - 20)
    settled.payments.create!(organization: @org, amount: 90, paid_on: Date.current, bank_account: @bank)
    draft    = create_bill(@org, vendor: "Maybe", amount: 10, category: @hosting, payable: @ap, state: "draft")

    get bills_path(status: "unpaid")
    assert_select "nav.chips a[aria-current=page]", text: "Unpaid"
    assert_select row(old_bill), 1
    assert_select row(new_bill), 1
    assert_select row(settled), 0
    assert_select row(draft), 0
    ids = css_select("tbody tr").map { |tr| tr["id"] }
    assert_equal [ old_bill, new_bill ].map { |d| ActionView::RecordIdentifier.dom_id(d) }, ids
  end
end

require "test_helper"

# One receivable account and one payable account, chosen in Settings. The
# invoice, bill and recurring-template forms never ask.
class ControlAccountsTest < ActionDispatch::IntegrationTest
  setup do
    @org = organizations(:one)
    sign_in_as_launchpad_user(@org)
    @ar      = Plutus::Asset.create!(tenant: @org, name: "Accounts Receivable", code: "1200")
    @ap      = Plutus::Liability.create!(tenant: @org, name: "Accounts Payable", code: "2000")
    @sales   = Plutus::Revenue.create!(tenant: @org, name: "Sales", code: "4100")
    @hosting = Plutus::Expense.create!(tenant: @org, name: "Hosting", code: "6820")
  end

  def line(amount, account) = { "0" => { description: "Line", quantity: 1, unit_amount: amount, account_id: account.id } }

  test "an invoice takes the receivable account from Settings and the form does not offer one" do
    @org.settings.update!(receivable_account: @ar)
    get new_invoice_path
    assert_select "select[name='document[documentable_attributes][receivable_account_id]']", 0

    post invoices_path, params: { document: { date: "2026-10-01", documentable_attributes: { client_name: "Acme", due_date: "2026-10-31" }, line_items_attributes: line(100, @sales) }, approve: "1" }
    doc = @org.documents.invoices.sole
    assert_equal @ar, doc.invoice.receivable_account
    assert_equal BigDecimal("100"), @ar.balance
  end

  test "a bill takes the payable account from Settings and the form does not offer one" do
    @org.settings.update!(payable_account: @ap)
    get new_bill_path
    assert_select "select[name='document[documentable_attributes][payable_account_id]']", 0

    post bills_path, params: { document: { date: "2026-10-01", documentable_attributes: { vendor: "AWS" }, line_items_attributes: line(45, @hosting) }, approve: "1" }
    assert_equal @ap, @org.documents.bills.sole.bill.payable_account
    assert_equal BigDecimal("45"), @ap.balance
  end

  test "a recurring template takes the receivable account from Settings too" do
    @org.settings.update!(receivable_account: @ar)
    get new_recurring_invoice_path
    assert_select "select[name='recurring_invoice[receivable_account_id]']", 0

    post recurring_invoices_path, params: { recurring_invoice: { client_name: "Acme", frequency: "monthly", interval: 1, next_run_on: Date.current,
                                                                 line_items_attributes: line(500, @sales) } }
    template = @org.recurring_invoices.sole
    assert_equal @ar, template.receivable_account
    assert_equal @ar, template.generate!.invoice.receivable_account
  end

  test "without the account in Settings, the forms send you there instead" do
    get new_invoice_path
    assert_redirected_to settings_path
    assert_match(/receivable/i, flash[:alert])
    post invoices_path, params: { document: { date: "2026-10-01", documentable_attributes: { client_name: "Acme", due_date: "2026-10-31" }, line_items_attributes: line(100, @sales) } }
    assert_redirected_to settings_path
    assert_equal 0, @org.documents.count

    get new_bill_path
    assert_redirected_to settings_path
    assert_match(/payable/i, flash[:alert])

    get new_recurring_invoice_path
    assert_redirected_to settings_path
  end

  test "an invoice imported with its own account keeps it when edited" do
    other = Plutus::Asset.create!(tenant: @org, name: "Old receivables", code: "1210")
    @org.settings.update!(receivable_account: @ar)
    doc = create_invoice(@org, client_name: "Acme", amount: 10, receivable: other, revenue: @sales)
    patch invoice_path(doc), params: { document: { reference: "R-1" } }
    assert_equal other, doc.reload.invoice.receivable_account
  end
end

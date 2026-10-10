require "test_helper"

# "Bill to" on the expense and bill forms; the page then says who it is
# billable to and that it has not been invoiced yet.
class BillableFlagTest < ActionDispatch::IntegrationTest
  setup do
    @org = organizations(:one)
    sign_in_as_launchpad_user(@org)
    @ar      = Plutus::Asset.create!(tenant: @org, name: "AR", code: "1200")
    @ap      = Plutus::Liability.create!(tenant: @org, name: "AP", code: "2000")
    @travel  = Plutus::Expense.create!(tenant: @org, name: "Travel", code: "6812")
    @sales   = Plutus::Revenue.create!(tenant: @org, name: "Sales", code: "4100")
    @bank    = create_bank_account(@org, name: "Checking")
    @org.settings.update!(receivable_account: @ar, payable_account: @ap, bank_account: @bank)
    @northwind = @org.contacts.create!(name: "Northwind", kind: "customer")
    @delta     = @org.contacts.create!(name: "Delta", kind: "vendor")
  end

  def line(amount) = { "0" => { description: "DTW–DEN", quantity: 1, unit_amount: amount, account_id: @travel.id } }

  test "an expense is flagged on its form and its page says so" do
    get new_expense_path
    assert_select "select[name='document[billable_to_id]']" do
      assert_select "option[value=?]", @northwind.id.to_s, text: "Northwind"
      assert_select "option[value=?]", @delta.id.to_s, 0, "vendors are not offered as customers"
      assert_select "option[value='']", text: "Not billable"
    end

    post expenses_path, params: { document: { date: "2026-03-14", contact_id: @delta.id, billable_to_id: @northwind.id,
                                              documentable_attributes: { bank_account_id: @bank.id }, line_items_attributes: line(500) } }
    exp = @org.documents.expenses.sole
    assert_equal @northwind, exp.billable_to

    get expense_path(exp)
    assert_select ".billable", text: /Billable to Northwind.*not yet invoiced/m
    assert_select ".billable a[href=?]", new_invoice_path(contact_id: @northwind.id), text: "New invoice for Northwind"

    get edit_expense_path(exp)
    assert_select "select[name='document[billable_to_id]'] option[selected][value=?]", @northwind.id.to_s
    patch expense_path(exp), params: { document: { billable_to_id: "" } }
    assert_nil exp.reload.billable_to
    get expense_path(exp)
    assert_select ".billable", 0
  end

  test "a bill has the same field; an invoice does not" do
    get new_bill_path
    assert_select "select[name='document[billable_to_id]']"
    get new_invoice_path
    assert_select "select[name='document[billable_to_id]']", 0
  end

  test "a new invoice can start with the customer given" do
    get new_invoice_path(contact_id: @northwind.id)
    assert_select "select[name='document[contact_id]'] option[selected][value=?]", @northwind.id.to_s
  end
end

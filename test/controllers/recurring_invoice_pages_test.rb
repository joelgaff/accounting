require "test_helper"

class RecurringInvoicePagesTest < ActionDispatch::IntegrationTest
  setup do
    @org = organizations(:one)
    sign_in_as_launchpad_user(@org)
    @ar    = Plutus::Asset.create!(tenant: @org, name: "AR", code: "1200")
    @sales = Plutus::Revenue.create!(tenant: @org, name: "Sales", code: "200")
    @org.settings.update!(receivable_account: @ar)
  end

  test "the template form chooses between draft and approved on generation" do
    get new_recurring_invoice_path
    assert_select "input[name='recurring_invoice[approve_on_generate]'][value='true']"
    assert_select "input[name='recurring_invoice[approve_on_generate]'][value='false']"

    post recurring_invoices_path, params: { recurring_invoice: {
      client_name: "Acme", frequency: "monthly", interval: 1, next_run_on: Date.current,
      approve_on_generate: "false",
      line_items_attributes: { "0" => { description: "Retainer", quantity: 1, unit_amount: 500, account_id: @sales.id } } } }
    template = @org.recurring_invoices.sole
    assert_not template.approve_on_generate?
  end
end

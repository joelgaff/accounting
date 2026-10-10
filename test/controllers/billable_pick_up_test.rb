require "test_helper"

# On an invoice, a customer's unbilled costs are offered under the lines; a
# tick adds them as lines, marked up. Saving records what each line rebills.
class BillablePickUpTest < ActionDispatch::IntegrationTest
  setup do
    @org = organizations(:one)
    sign_in_as_launchpad_user(@org)
    @ar       = Plutus::Asset.create!(tenant: @org, name: "AR", code: "1200")
    @sales    = Plutus::Revenue.create!(tenant: @org, name: "Sales", code: "4100")
    @billable = Plutus::Revenue.create!(tenant: @org, name: "Billable Expense Income", code: "4721")
    @travel   = Plutus::Expense.create!(tenant: @org, name: "Travel", code: "6812")
    @bank     = create_bank_account(@org, name: "Checking")
    @org.settings.update!(receivable_account: @ar, bank_account: @bank, billable_income_account: @billable)
    @northwind = @org.contacts.create!(name: "Northwind", kind: "customer")
    @acme      = @org.contacts.create!(name: "Acme", kind: "customer")
    @ticket = @org.documents.create!(date: Date.new(2026, 3, 14), contact_name: "Delta", billable_to: @northwind, documentable: Expense.new(bank_account: @bank),
                                     line_items_attributes: [ { description: "DTW–DEN", quantity: 1, unit_amount: 500, account_id: @travel.id } ])
    @hotel  = create_expense(@org, vendor: "Marriott", amount: 300, category: @travel, bank_account: @bank, billable_to: @northwind, date: Date.new(2026, 3, 15))
    @theirs = create_expense(@org, vendor: "Zoom", amount: 15, category: @travel, bank_account: @bank, billable_to: @acme)
  end

  def frame_id = ActionView::RecordIdentifier.dom_id(@org, :billable_expenses)

  test "the panel lists the customer's unbilled costs with rows ready to add, marked up" do
    get contact_billable_expenses_path(@northwind, markup: 10)
    assert_response :success
    assert_select "turbo-frame##{frame_id}" do
      assert_select "legend", text: /Billable expenses for Northwind/
      assert_select "input[data-billable-target=markup][value='10']"
      assert_select "li[data-cost-id=?]", @ticket.id.to_s do
        assert_select "input[type=checkbox][data-cost-id=?]", @ticket.id.to_s
        assert_select "label", text: /Mar 14, 2026.*Delta.*DTW–DEN.*\$550\.00/m
        assert_select "template" do
          assert_select "input[name='document[line_items_attributes][NEW_RECORD][rebills_document_id]'][value=?]", @ticket.id.to_s
          assert_select "input[name='document[line_items_attributes][NEW_RECORD][description]'][value=?]", "DTW–DEN"
          assert_select "input[name='document[line_items_attributes][NEW_RECORD][unit_amount]'][value=?]", "550.0"
          assert_select "select[name='document[line_items_attributes][NEW_RECORD][account_id]'] option[selected][value=?]", @billable.id.to_s
        end
      end
      assert_select "li[data-cost-id=?]", @hotel.id.to_s
      assert_select "li[data-cost-id=?]", @theirs.id.to_s, 0, "another customer's cost"
    end
  end

  test "a billed cost and a customer with nothing to bill" do
    inv = create_invoice(@org, contact: @northwind, amount: 1, receivable: @ar, revenue: @sales, state: "draft")
    inv.line_items.first.update!(rebills: @ticket)
    get contact_billable_expenses_path(@northwind)
    assert_select "li[data-cost-id=?]", @ticket.id.to_s, 0
    assert_select "li[data-cost-id=?]", @hotel.id.to_s

    @hotel.update!(billable_to: nil)
    get contact_billable_expenses_path(@northwind)
    assert_select "turbo-frame##{frame_id}"
    assert_select "legend", 0, "nothing to offer, nothing shown"
  end

  test "the invoice form carries the frame, pointed at the chosen customer" do
    get new_invoice_path(contact_id: @northwind.id)
    assert_select "form[data-controller~=billable]"
    assert_select "select[name='document[contact_id]'][data-action*='billable#customerChanged']"
    assert_select "turbo-frame##{frame_id}[src=?]", contact_billable_expenses_path(@northwind)

    get new_invoice_path
    assert_select "turbo-frame##{frame_id}:not([src])"
  end

  test "saving the invoice with picked-up lines bills the costs, and the page says what each line rebills" do
    post invoices_path, params: { document: {
      date: Date.current.iso8601, contact_id: @northwind.id,
      documentable_attributes: { client_name: "Northwind", due_date: (Date.current + 30).iso8601 },
      line_items_attributes: {
        "0" => { description: "Timing", quantity: 1, unit_amount: 1200, account_id: @sales.id },
        "1" => { description: "DTW–DEN", quantity: 1, unit_amount: 550, account_id: @billable.id, rebills_document_id: @ticket.id } } } }
    inv = @org.documents.invoices.order(:id).last
    assert_equal @ticket, inv.line_items.last.rebills
    assert_equal inv, @ticket.reload.billed_on

    get invoice_path(inv)
    assert_select ".rebills a[href=?]", expense_path(@ticket), text: /Expense · Delta/
    get print_invoice_path(inv)
    assert_select ".rebills", 0
    assert_no_match(/rebills/i, response.body)

    get expense_path(@ticket)
    assert_select ".billable a[href=?]", invoice_path(inv), text: /#{Regexp.escape(inv.label)}/
    assert_select ".billable", text: /Billed on/
  end

  test "a cost already on another invoice is refused with its number" do
    first = create_invoice(@org, contact: @northwind, amount: 1, receivable: @ar, revenue: @sales, state: "draft")
    first.line_items.first.update!(rebills: @ticket)
    post invoices_path, params: { document: {
      date: Date.current.iso8601, contact_id: @northwind.id,
      documentable_attributes: { client_name: "Northwind", due_date: (Date.current + 30).iso8601 },
      line_items_attributes: { "0" => { description: "DTW–DEN", quantity: 1, unit_amount: 550, account_id: @billable.id, rebills_document_id: @ticket.id } } } }
    assert_response :unprocessable_entity
    assert_match(/already billed on #{Regexp.escape(first.label)}/, response.body)
  end
end

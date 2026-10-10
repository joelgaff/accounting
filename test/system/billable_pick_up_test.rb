require "application_system_test_case"

# Ticking a billable cost on the invoice form adds its lines and moves the
# total; unticking takes them away. Desktop and phone.
class BillablePickUpTest < ApplicationSystemTestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @ar       = Plutus::Asset.create!(tenant: @org, name: "AR", code: "1200")
    @sales    = Plutus::Revenue.create!(tenant: @org, name: "Timing Services", code: "4700")
    @billable = Plutus::Revenue.create!(tenant: @org, name: "Billable Expense Income", code: "4721")
    @travel   = Plutus::Expense.create!(tenant: @org, name: "Travel", code: "6812")
    @bank     = create_bank_account(@org, name: "Checking")
    @org.settings.update!(receivable_account: @ar, bank_account: @bank, billable_income_account: @billable)
    @northwind = @org.contacts.create!(name: "Northwind Trail Series", kind: "customer")
    @ticket = @org.documents.create!(date: Date.new(2026, 3, 14), contact_name: "Delta", billable_to: @northwind, documentable: Expense.new(bank_account: @bank),
                                     line_items_attributes: [ { description: "DTW–DEN", quantity: 1, unit_amount: 500, account_id: @travel.id },
                                                              { description: "Bag fee", quantity: 1, unit_amount: 35, account_id: @travel.id } ])
    sign_in_as_launchpad_user(@org)
  end

  def ticket_rows = "tbody[data-line-items-target=rows] tr[data-rebills='#{@ticket.id}']"

  def pick_up_and_check
    visit new_invoice_path(contact_id: @northwind.id)
    assert_selector "legend", text: /Billable expenses for Northwind/i
    fill_in "Markup %", with: "10"
    find("#billable_markup").send_keys(:tab)                      # leave the field: the panel re-fetches with the markup
    assert_selector "li[data-cost-id='#{@ticket.id}'] .billable-amount", text: "$588.50"
    find("input[type=checkbox][data-cost-id='#{@ticket.id}']").click
    assert_selector ticket_rows, count: 2
    assert_selector "#{ticket_rows} input[name$='[description]'][value='DTW–DEN']"
    assert_selector "#{ticket_rows} input[name$='[unit_amount]'][value='550.0']"
    assert_selector "[data-line-items-target=total]", text: "$588.50"
    find("input[type=checkbox][data-cost-id='#{@ticket.id}']").click
    assert_no_selector ticket_rows
    assert_selector "[data-line-items-target=total]", text: "$0.00"
  end

  test "pick up a cost on a desktop, save, and the invoice carries it" do
    pick_up_and_check
    find("input[type=checkbox][data-cost-id='#{@ticket.id}']").click
    assert_selector ticket_rows, count: 2
    click_on "Save draft"
    assert_selector "h1", text: /Invoice/
    inv = @org.documents.invoices.order(:id).last
    assert_equal [ @ticket, @ticket ], inv.line_items.map(&:rebills)
    assert_equal [ 550, 38.5 ], inv.line_items.map(&:unit_amount)
    assert_equal inv, @ticket.reload.billed_on
    shoot("billable picked up")
  end

  test "the panel works on a phone" do
    on_phone
    pick_up_and_check
    assert_fits_viewport("invoice form with billable panel")
    shoot("billable phone")
  end
end

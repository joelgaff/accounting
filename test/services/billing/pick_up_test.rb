require "test_helper"

# Billing::PickUp builds the invoice lines for billable costs: one invoice
# line per expense line, marked up on the unit price, tax and tracking carried
# across, account from Settings or the cost's own. Nothing is saved.
class BillingPickUpTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @ar       = Plutus::Asset.create!(tenant: @org, name: "AR", code: "1200")
    @sales    = Plutus::Revenue.create!(tenant: @org, name: "Sales", code: "4100")
    @billable = Plutus::Revenue.create!(tenant: @org, name: "Billable Expense Income", code: "4721")
    @travel   = Plutus::Expense.create!(tenant: @org, name: "Travel", code: "6812")
    @meals    = Plutus::Expense.create!(tenant: @org, name: "Meals", code: "6802")
    @bank     = create_bank_account(@org, name: "Checking")
    @gst      = @org.tax_rates.create!(name: "GST", rate: 0.1, liability_account: Plutus::Liability.create!(tenant: @org, name: "GST owed"))
    @klass    = @org.tracking_categories.create!(name: "Class", options_attributes: [ { name: "Summit Races" } ])
    @summit   = @klass.options.first
    @org.settings.update!(receivable_account: @ar, bank_account: @bank)
    @northwind = @org.contacts.create!(name: "Northwind", kind: "customer")
    @trip = @org.documents.create!(date: Date.new(2026, 3, 14), contact_name: "Delta", billable_to: @northwind,
                                   documentable: Expense.new(bank_account: @bank),
                                   line_items_attributes: [
                                     { description: "DTW–DEN", quantity: 1, unit_amount: 500, account_id: @travel.id, tax_rate_id: @gst.id, tracking_option_ids: [ @summit.id ] },
                                     { description: "Dinner", quantity: 3, unit_amount: 40, account_id: @meals.id } ])
    @invoice = @org.documents.build(date: Date.current, contact: @northwind, documentable: Invoice.new(receivable_account: @ar))
  end

  test "one invoice line per expense line, marked up on the unit, tax and tracking carried, account from Settings" do
    @org.settings.update!(billable_income_account: @billable)
    lines = Billing::PickUp.new(@invoice, [ @trip ], markup: 10).lines

    assert_equal 2, lines.size
    assert lines.all?(&:new_record?)
    assert_equal @invoice.line_items.to_a, lines, "built on the invoice, not saved"

    flight, dinner = lines
    assert_equal "DTW–DEN", flight.description
    assert_equal 1, flight.quantity
    assert_equal 550, flight.unit_amount
    assert_equal @billable, flight.account
    assert_equal @gst, flight.tax_rate
    assert_equal [ @summit.id ], flight.tracking_option_ids
    assert_equal @trip, flight.rebills

    assert_equal 3, dinner.quantity
    assert_equal 44, dinner.unit_amount, "markup on the unit price, quantity as it was"
    assert_nil dinner.tax_rate
    assert_equal @trip, dinner.rebills

    assert_equal 500, @trip.reload.line_items.first.unit_amount, "the cost keeps its real price"
  end

  test "no Settings account: the cost's own account; no markup: the same price; odd markups round to the cent" do
    lines = Billing::PickUp.new(@invoice, [ @trip ], markup: nil).lines
    assert_equal [ @travel, @meals ], lines.map(&:account)
    assert_equal [ 500, 40 ], lines.map(&:unit_amount)

    @invoice.line_items.clear
    lines = Billing::PickUp.new(@invoice, [ @trip ], markup: "12.5").lines
    assert_equal [ 562.5, 45 ], lines.map(&:unit_amount)
  end

  test "a cost that is not the customer's, or already billed, is left out" do
    other = @org.contacts.create!(name: "Acme", kind: "customer")
    theirs = create_expense(@org, vendor: "Zoom", amount: 15, category: @travel, bank_account: @bank, billable_to: other)
    lines = Billing::PickUp.new(@invoice, [ @trip, theirs ], markup: 0).lines
    assert_equal [ @trip ], lines.map(&:rebills).uniq
  end
end

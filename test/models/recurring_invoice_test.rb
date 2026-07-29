require "test_helper"

class RecurringInvoiceTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @ar    = Plutus::Asset.create!(tenant: @org, name: "AR")
    @sales = Plutus::Revenue.create!(tenant: @org, name: "Sales")
  end

  def build_recurring(**overrides)
    ri = @org.recurring_invoices.build({
      client_name:        "Acme Retainer",
      receivable_account: @ar,
      frequency:          "monthly",
      interval:           1,
      next_run_on:        Date.current,
      line_items_attributes: [
        { description: "Monthly retainer", quantity: 1, unit_amount: 500, account_id: @sales.id }
      ]
    }.merge(overrides))
    ri.save!
    ri
  end

  test "generate! creates an Invoice with the line-items template and advances next_run_on" do
    ri = build_recurring(next_run_on: Date.new(2026, 7, 15))
    invoice = nil
    assert_difference -> { @org.invoices.count }, 1 do
      invoice = ri.generate!(as_of: Date.new(2026, 7, 15))
    end
    assert_equal BigDecimal("500"), invoice.amount
    assert_equal 1, invoice.line_items.size
    ri.reload
    assert_equal Date.new(2026, 8, 15), ri.next_run_on
  end

  test "weekly interval advances by 7 * interval days" do
    ri = build_recurring(frequency: "weekly", interval: 2, next_run_on: Date.new(2026, 7, 1))
    ri.generate!(as_of: Date.new(2026, 7, 1))
    assert_equal Date.new(2026, 7, 15), ri.reload.next_run_on
  end

  test "deactivates when advancing past end_on" do
    ri = build_recurring(next_run_on: Date.new(2026, 7, 1), end_on: Date.new(2026, 7, 10))
    ri.generate!(as_of: Date.new(2026, 7, 1))
    ri.reload
    refute ri.active?
    assert_equal Date.new(2026, 8, 1), ri.next_run_on
  end

  test "GenerateRecurringInvoicesJob picks up due templates only" do
    due_today   = build_recurring(next_run_on: Date.current)
    future      = build_recurring(next_run_on: Date.current + 5.days, client_name: "Future")
    paused      = build_recurring(next_run_on: Date.current, active: false, client_name: "Paused")

    assert_difference -> { @org.invoices.count }, 1 do
      GenerateRecurringInvoicesJob.new.perform(as_of: Date.current)
    end
    assert_equal Date.current + 5.days, future.reload.next_run_on   # unchanged
    refute paused.reload.active?
  end
end

require "test_helper"

class RecurringInvoiceTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

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
    assert_difference -> { @org.documents.invoices.count }, 1 do
      invoice = ri.generate!(as_of: Date.new(2026, 7, 15))
    end
    assert_equal BigDecimal("500"), invoice.total
    assert_equal 1, invoice.line_items.size
    ri.reload
    assert_equal Date.new(2026, 8, 15), ri.next_run_on
  end

  test "a template approves what it generates unless told to leave a draft" do
    contact = @org.contacts.create!(name: "Acme", kind: "customer", email: "ap@acme.example")
    approving = build_recurring(contact: contact, email_on_generate: true)
    drafting  = build_recurring(contact: contact, email_on_generate: true, approve_on_generate: false, client_name: "Drafts")
    assert approving.approve_on_generate?, "approving is the default, as before"

    posted = nil
    assert_enqueued_emails 1 do
      posted = approving.generate!(as_of: Date.current)
    end
    assert posted.approved?
    assert_equal 1, posted.entries.count

    draft = nil
    assert_no_enqueued_emails do
      draft = drafting.generate!(as_of: Date.current)
    end
    assert draft.draft?
    assert_equal 0, draft.entries.count
    assert_equal BigDecimal("500"), draft.total
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

    assert_difference -> { @org.documents.invoices.count }, 1 do
      GenerateRecurringInvoicesJob.new.perform(as_of: Date.current)
    end
    assert_equal Date.current + 5.days, future.reload.next_run_on   # unchanged
    refute paused.reload.active?
  end
end

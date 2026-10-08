require "test_helper"

# An approved invoice is sent once it has been emailed from here, or marked
# sent because it went out some other way. Drafts cannot be sent.
class InvoiceSentTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @ar    = Plutus::Asset.create!(tenant: @org, name: "AR")
    @sales = Plutus::Revenue.create!(tenant: @org, name: "Sales")
  end

  test "mark as sent and unsent, with a history line each way" do
    inv = create_invoice(@org, client_name: "Acme", amount: 10, receivable: @ar, revenue: @sales)
    assert_not inv.invoice.sent?
    inv.invoice.mark_sent!
    assert inv.invoice.reload.sent?
    assert_in_delta Time.current, inv.invoice.sent_at, 5
    assert_equal "sent", inv.events.last.action
    assert_equal "Marked as sent", inv.events.last.title

    inv.invoice.mark_unsent!
    assert_not inv.invoice.reload.sent?
    assert_equal "unsent", inv.events.last.action
  end

  test "a draft cannot be marked sent" do
    draft = create_invoice(@org, client_name: "Acme", amount: 10, receivable: @ar, revenue: @sales, state: "draft")
    assert_raises(ActiveRecord::RecordInvalid) { draft.invoice.mark_sent! }
    assert_not draft.invoice.reload.sent?
  end

  test "emailing an invoice marks it sent without a second history line" do
    inv = create_invoice(@org, client_name: "Acme", amount: 10, receivable: @ar, revenue: @sales)
    inv.invoice.mark_sent!(quietly: true)
    assert inv.invoice.reload.sent?
    assert_equal 0, inv.events.where(action: "sent").count
  end
end

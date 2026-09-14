require "test_helper"

class DocumentHistoryTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    Current.user = @org.users.create!(launchpad_public_id: "u-test", email_address: "j@example.com", name: "Joel")
    @ar    = Plutus::Asset.create!(tenant: @org, name: "AR")
    @sales = Plutus::Revenue.create!(tenant: @org, name: "Sales")
    @bank  = create_bank_account(@org, name: "Checking")
  end

  teardown { Current.reset }

  test "creating, editing, paying and voiding leave a readable trail" do
    inv = create_invoice(@org, client_name: "Acme", amount: 500, receivable: @ar, revenue: @sales)
    created = inv.events.sole
    assert_equal "created", created.action
    assert_equal "Joel", created.actor_name
    assert_includes created.detail_lines, "Total $500.00"

    inv.update_and_repost!(reference: "PO-9", documentable_attributes: { client_name: "Acme Ltd" },
                           line_items_attributes: [ { id: inv.line_items.sole.id, unit_amount: 600 } ])
    edit = inv.events.newest_first.first
    assert_equal "edited", edit.action
    assert_equal [ nil, "PO-9" ],           edit.details["changes"]["Reference"]
    assert_includes edit.detail_lines, "Reference: (blank) → PO-9"
    assert_equal [ "Acme", "Acme Ltd" ],   edit.details["changes"]["Customer"]
    assert_equal [ "$500.00", "$600.00" ], edit.details["changes"]["Total"]
    assert_equal [ "Acme", "Acme Ltd" ],   edit.details["changes"]["Contact"]

    inv.update_and_repost!(memo: nil)
    assert_equal "edited", inv.events.newest_first.first.action, "a no-op edit records nothing new"
    assert_equal 2, inv.events.count

    payment = inv.payments.create!(organization: @org, amount: 200, paid_on: Date.current, bank_account: @bank)
    paid = inv.events.newest_first.first
    assert_equal "payment_recorded", paid.action
    assert_equal "Payment received", paid.title
    assert_match(/\$200\.00 · Checking/, paid.detail_lines.first)

    payment.unwind!
    assert_equal "payment_removed", inv.events.newest_first.first.action

    inv.payments.create!(organization: @org, amount: 100, paid_on: Date.current, bank_account: @bank)
    inv.void!
    voided = inv.events.newest_first.first
    assert_equal "voided", voided.action
    assert_includes voided.detail_lines, "1 payment removed ($100.00)"
    assert_equal %w[voided payment_recorded payment_removed payment_recorded edited created], inv.events.newest_first.map(&:action), "a void summarises its payments in one line"
  end

  test "reconcile links and unlinks are recorded on the document" do
    hosting = Plutus::Expense.create!(tenant: @org, name: "Hosting")
    exp = create_expense(@org, vendor: "DO", amount: 30, category: hosting, bank_account: @bank)
    txn = @org.bank_transactions.create!(bank_account: @bank, posted_on: Date.current, amount: -30, payee: "DIGITALOCEAN", description: "x")
    Reconciliation::MatchDocument.new(txn, exp).call
    assert_equal "matched", exp.events.newest_first.first.action
    assert_match(/Checking .* \$30\.00 · DIGITALOCEAN/, exp.events.newest_first.first.detail_lines.first)
    Reconciliation::Unmatch.new(txn).call
    assert_equal "unmatched", exp.reload.events.newest_first.first.action
  end

  test "events without a user name the import or the system" do
    Current.user = nil
    inv = create_invoice(@org, client_name: "A", amount: 10, receivable: @ar, revenue: @sales, source: "xero_import")
    assert_equal "Xero import", inv.events.sole.actor_name
    inv2 = create_invoice(@org, client_name: "B", amount: 10, receivable: @ar, revenue: @sales)
    assert_equal "System", inv2.events.sole.actor_name
  end

  test "the invoice PDF renders with any characters the lines carry" do
    inv = create_invoice(@org, client_name: "Café Zoë — “quotes” ✓", amount: 1234.5, receivable: @ar, revenue: @sales)
    inv.line_items.sole.update!(description: "Timing – 5 km · résumé ✓ ünïcode")
    pdf = InvoicePdf.new(inv).render
    assert pdf.start_with?("%PDF-")
    assert_operator pdf.bytesize, :>, 5_000
    assert_equal "invoice-#{inv.id}.pdf", InvoicePdf.filename(inv)
  end
end

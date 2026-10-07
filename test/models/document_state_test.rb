require "test_helper"

class DocumentStateTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @ar    = Plutus::Asset.create!(tenant: @org, name: "AR")
    @sales = Plutus::Revenue.create!(tenant: @org, name: "Sales")
  end

  test "a document is draft or approved, nothing else, and approved unless told otherwise" do
    doc = create_invoice(@org, client_name: "Acme", amount: 10, receivable: @ar, revenue: @sales)
    assert_equal "approved", doc.state
    assert doc.approved?
    assert_not doc.draft?

    doc.state = "bogus"
    assert_not doc.valid?
    assert_includes doc.errors[:state].join, "not included"
  end

  test "a draft posts nothing until it is approved, and then exactly once" do
    doc = create_invoice(@org, client_name: "Acme", amount: 10, receivable: @ar, revenue: @sales, state: "draft")
    assert doc.draft?
    assert_equal 0, doc.entries.count

    doc.approve!
    assert doc.reload.approved?
    assert_equal 1, doc.entries.count
    assert_equal BigDecimal("10"), @ar.balance
    assert_equal "approved", doc.events.last.action

    assert_raises(ActiveRecord::RecordInvalid) { doc.approve! }
    assert_equal 1, doc.entries.count
  end

  test "editing a draft keeps it unposted" do
    doc = create_invoice(@org, client_name: "Acme", amount: 10, receivable: @ar, revenue: @sales, state: "draft")
    doc.update_and_repost!(reference: "quote 7", line_items_attributes: [ { id: doc.line_items.first.id, unit_amount: 25 } ])
    assert_equal BigDecimal("25"), doc.reload.total
    assert_equal 0, doc.entries.count
    assert doc.draft?
  end

  test "an approved document with nothing against it can go back to draft" do
    doc = create_invoice(@org, client_name: "Acme", amount: 10, receivable: @ar, revenue: @sales)
    doc.unapprove!
    assert doc.reload.draft?
    assert_equal 0, doc.entries.count
    assert_equal BigDecimal("0"), @ar.balance
  end
end

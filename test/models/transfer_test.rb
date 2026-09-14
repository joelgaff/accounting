require "test_helper"

class TransferTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @checking = create_bank_account(@org, name: "Checking")
    @savings  = create_bank_account(@org, name: "Savings", kind: "savings")
  end

  def create_transfer(amount, from: @checking, to: @savings)
    @org.documents.create!(date: Date.current, total: amount, documentable: Transfer.new(from_bank_account: from, to_bank_account: to))
  end

  test "moves money between accounts and keeps the total it was given" do
    tr = create_transfer(500)
    assert_equal BigDecimal("500"),  tr.total
    assert_equal BigDecimal("-500"), @checking.balance
    assert_equal BigDecimal("500"),  @savings.balance
    assert_equal "Checking → Savings", tr.party_name
    assert_empty tr.line_items
  end

  test "rejects the same account on both sides and a zero amount" do
    doc = @org.documents.build(date: Date.current, total: 10, documentable: Transfer.new(from_bank_account: @checking, to_bank_account: @checking))
    assert_not doc.valid?
    assert doc.errors.full_messages.any? { |m| m =~ /differ/ }
    assert_not @org.documents.build(date: Date.current, total: 0, documentable: Transfer.new(from_bank_account: @checking, to_bank_account: @savings)).valid?
  end

  test "knows which statement line each side expects and whether it has arrived" do
    tr = create_transfer(200).transfer
    assert_equal BigDecimal("-200"), tr.expected_amount_for(@checking)
    assert_equal BigDecimal("200"),  tr.expected_amount_for(@savings)
    assert tr.awaiting_side?(@checking)
    @org.bank_transactions.create!(bank_account: @checking, posted_on: Date.current, amount: -200, description: "TFR").update!(document: tr.document, status: "matched")
    assert_not tr.reload.awaiting_side?(@checking)
    assert tr.awaiting_side?(@savings)
  end
end

require "test_helper"

class LedgerTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @bank    = Plutus::Asset.create!(tenant: @org,     name: "Bank")
    @revenue = Plutus::Revenue.create!(tenant: @org,   name: "Sales")
  end

  test "posts a balanced entry" do
    assert_difference -> { Plutus::Entry.count } => 1 do
      Ledger.post(
        description: "test",
        commercial_document: nil,
        debits:  [{ account: @bank,    amount: 100 }],
        credits: [{ account: @revenue, amount: 100 }]
      )
    end

    assert_equal BigDecimal("100"), @bank.balance
    assert_equal BigDecimal("100"), @revenue.balance
  end

  test "rolls back and raises when unbalanced" do
    assert_no_difference -> { Plutus::Entry.count } do
      assert_raises(ActiveRecord::RecordInvalid) do
        Ledger.post(
          description: "bad",
          commercial_document: nil,
          debits:  [{ account: @bank,    amount: 100 }],
          credits: [{ account: @revenue, amount: 50 }]
        )
      end
    end
  end

  test "lookup and balance are tenant-scoped and forgiving of missing names" do
    assert_equal @bank, Ledger.lookup("Bank")
    assert_nil    Ledger.lookup("Nope")
    assert_equal BigDecimal("0"), Ledger.balance("Nope")
  end
end

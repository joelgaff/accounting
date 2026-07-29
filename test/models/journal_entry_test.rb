require "test_helper"

class JournalEntryTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @office  = Plutus::Expense.create!(tenant: @org, name: "Office")
    @meals   = Plutus::Expense.create!(tenant: @org, name: "Meals")
    @bank    = Plutus::Asset.create!(tenant: @org, name: "Bank")
  end

  test "balanced 3-line journal posts to ledger" do
    je = @org.journal_entries.create!(
      posted_on: Date.current, narrative: "Petty cash reimb",
      lines_attributes: [
        { account_id: @office.id, debit_amount: 100 },
        { account_id: @meals.id,  debit_amount: 50 },
        { account_id: @bank.id,   credit_amount: 150 }
      ]
    )
    assert je.balanced?
    assert_equal BigDecimal("100"), @office.balance
    assert_equal BigDecimal("50"),  @meals.balance
    assert_equal BigDecimal("-150"), @bank.balance
    assert_equal Plutus::DebitAmount.sum(:amount), Plutus::CreditAmount.sum(:amount)
  end

  test "unbalanced entry is invalid, does not post" do
    je = @org.journal_entries.build(
      posted_on: Date.current, narrative: "Bad",
      lines_attributes: [
        { account_id: @office.id, debit_amount: 100 },
        { account_id: @bank.id,   credit_amount: 90 }
      ]
    )
    assert_not je.valid?
    assert_match(/debits.*must equal credits/, je.errors[:base].join)
  end

  test "single-line entry is invalid" do
    je = @org.journal_entries.build(
      posted_on: Date.current, narrative: "Only one line",
      lines_attributes: [{ account_id: @office.id, debit_amount: 100 }]
    )
    assert_not je.valid?
    assert_includes je.errors[:base].join, "at least two lines"
  end

  test "line with both debit and credit is invalid" do
    line = JournalLine.new(account: @office, debit_amount: 10, credit_amount: 10)
    assert_not line.valid?
    assert_includes line.errors[:base].join, "either a debit or a credit"
  end
end

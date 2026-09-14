require "test_helper"

class ExpenseTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @hosting = Plutus::Expense.create!(tenant: @org, name: "Hosting")
    @bank    = create_bank_account(@org, name: "Bank")
  end

  test "an expense paid from a bank posts DR expense / CR bank" do
    create_expense(@org, vendor: "DigitalOcean", amount: 20, category: @hosting, bank_account: @bank)
    assert_equal BigDecimal("20"),  @hosting.balance
    assert_equal BigDecimal("-20"), @bank.balance
  end

  test "an expense paid from a credit card credits the card's liability" do
    card = create_bank_account(@org, name: "Card", kind: "credit_card")
    create_expense(@org, vendor: "DigitalOcean", amount: 20, category: @hosting, bank_account: card)
    assert_equal BigDecimal("20"), card.balance   # owed
  end

  test "is always paid and never settleable" do
    exp = create_expense(@org, vendor: "DO", amount: 20, category: @hosting, bank_account: @bank)
    assert_equal "paid", exp.status
    assert_not exp.settleable?
  end
end

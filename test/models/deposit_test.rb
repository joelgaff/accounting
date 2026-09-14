require "test_helper"

class DepositTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @bank  = create_bank_account(@org, name: "Bank")
    @sales = Plutus::Revenue.create!(tenant: @org, name: "Sales")
    @taxl  = Plutus::Liability.create!(tenant: @org, name: "Sales Tax Payable")
  end

  def create_deposit(amount:, tax_rate: nil, bank: @bank, **doc)
    @org.documents.create!(doc.merge(date: Date.current, documentable: Deposit.new(bank_account: bank),
      line_items_attributes: [ { description: "Sponsor", quantity: 1, unit_amount: amount, account_id: @sales.id, tax_rate_id: tax_rate&.id } ]))
  end

  test "posts DR bank / CR income, with tax to the liability" do
    rate = @org.tax_rates.create!(name: "GST 10%", rate: 0.10, liability_account: @taxl)
    dep  = create_deposit(amount: 100, tax_rate: rate)
    assert_equal BigDecimal("110"), dep.total
    assert_equal BigDecimal("110"), @bank.balance
    assert_equal BigDecimal("100"), @sales.balance
    assert_equal BigDecimal("10"),  @taxl.balance
    assert_equal "received", dep.status
    assert_not dep.settleable?
  end

  test "a deposit onto a credit card reduces what is owed" do
    card = create_bank_account(@org, name: "Card", kind: "credit_card")
    create_deposit(amount: 50, bank: card)
    assert_equal BigDecimal("-50"), card.balance
  end

  test "display name falls back from contact to memo to label" do
    dep = create_deposit(amount: 5, memo: "Cheque from the fair")
    assert_equal "Cheque from the fair", dep.display_name
    contact = @org.contacts.create!(name: "Fair Committee", kind: "customer")
    assert_equal "Fair Committee", create_deposit(amount: 5, contact: contact).display_name
  end
end

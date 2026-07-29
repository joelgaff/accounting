require "test_helper"

class InvoiceTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @ar    = Plutus::Asset.create!(tenant: @org,   name: "Accounts Receivable")
    @sales = Plutus::Revenue.create!(tenant: @org, name: "Sales")
  end

  test "creating an invoice posts a balanced entry" do
    assert_difference -> { Plutus::Entry.count } => 1 do
      @org.invoices.create!(
        client_name: "Acme",
        amount: 500,
        due_date: Date.current + 30,
        receivable_account: @ar,
        revenue_account: @sales
      )
    end

    assert_equal BigDecimal("500"), @ar.balance
    assert_equal BigDecimal("500"), @sales.balance
    assert_equal Plutus::DebitAmount.sum(:amount), Plutus::CreditAmount.sum(:amount)
  end

  test "rejects non-positive amounts" do
    invoice = @org.invoices.build(
      client_name: "Acme", amount: 0, due_date: Date.current,
      receivable_account: @ar, revenue_account: @sales
    )
    assert_not invoice.valid?
    assert_includes invoice.errors[:amount].join, "greater than 0"
  end
end

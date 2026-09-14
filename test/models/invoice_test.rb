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
      create_invoice(@org, client_name: "Acme", amount: 500, receivable: @ar, revenue: @sales)
    end

    assert_equal BigDecimal("500"), @ar.balance
    assert_equal BigDecimal("500"), @sales.balance
    assert_equal Plutus::DebitAmount.sum(:amount), Plutus::CreditAmount.sum(:amount)
  end

  test "rejects non-positive amounts" do
    doc = @org.documents.build(date: Date.current,
      documentable: Invoice.new(client_name: "Acme", due_date: Date.current, receivable_account: @ar),
      line_items_attributes: [ { description: "x", quantity: 1, unit_amount: 0, account_id: @sales.id } ])
    assert_not doc.valid?
    assert_includes doc.errors[:total].join, "greater than 0"
  end

  test "status reads open, overdue, partial, paid" do
    bank = create_bank_account(@org, name: "Bank")
    inv  = create_invoice(@org, client_name: "Acme", amount: 100, receivable: @ar, revenue: @sales, due_date: Date.current - 1)
    assert_equal "overdue", inv.status
    inv.payments.create!(organization: @org, amount: 40, paid_on: Date.current, bank_account: bank)
    assert_equal "partial", inv.reload.status
    inv.payments.create!(organization: @org, amount: 60, paid_on: Date.current, bank_account: bank)
    assert_equal "paid", inv.reload.status
  end
end

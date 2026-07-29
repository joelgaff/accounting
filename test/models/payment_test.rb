require "test_helper"

class PaymentTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @bank    = Plutus::Asset.create!(tenant: @org, name: "Bank")
    @ar      = Plutus::Asset.create!(tenant: @org, name: "AR")
    @sales   = Plutus::Revenue.create!(tenant: @org, name: "Sales")
    @ap      = Plutus::Liability.create!(tenant: @org, name: "AP")
    @hosting = Plutus::Expense.create!(tenant: @org, name: "Hosting")
  end

  test "payment received on invoice: DR bank, CR AR; invoice marked paid" do
    inv = @org.invoices.create!(client_name: "Acme", amount: 500, due_date: Date.current + 30,
                                receivable_account: @ar, revenue_account: @sales)

    assert_difference -> { Plutus::Entry.count }, 1 do
      inv.payments.create!(organization: @org, amount: 500, paid_on: Date.current, bank_account: @bank)
    end

    assert_equal BigDecimal("500"), @bank.balance
    assert_equal BigDecimal("0"),   @ar.balance
    inv.reload
    assert inv.paid?
    assert_equal "paid", inv.status
  end

  test "partial payment leaves balance due" do
    inv = @org.invoices.create!(client_name: "Acme", amount: 500, due_date: Date.current + 30,
                                receivable_account: @ar, revenue_account: @sales)
    inv.payments.create!(organization: @org, amount: 200, paid_on: Date.current, bank_account: @bank)

    assert_equal BigDecimal("300"), inv.reload.balance_due
    assert_equal "partial", inv.status
  end

  test "payment cannot exceed balance due" do
    inv = @org.invoices.create!(client_name: "Acme", amount: 100, due_date: Date.current + 30,
                                receivable_account: @ar, revenue_account: @sales)
    p = inv.payments.build(organization: @org, amount: 150, paid_on: Date.current, bank_account: @bank)
    assert_not p.valid?
    assert_match(/exceeds balance due/, p.errors[:amount].join)
  end

  test "payment made on expense-as-bill: DR AP, CR bank" do
    exp = @org.expenses.create!(vendor: "AWS", amount: 45, incurred_on: Date.current,
                                expense_account: @hosting, paid_from_account: @ap)
    # After creation: hosting balance = +45, AP balance = +45
    @bank.destroy  # not used yet
    @bank = Plutus::Asset.create!(tenant: @org, name: "Bank2")

    exp.payments.create!(organization: @org, amount: 45, paid_on: Date.current, bank_account: @bank)

    assert_equal BigDecimal("-45"), @bank.balance    # money out
    assert_equal BigDecimal("0"),   @ap.reload.balance
    exp.reload
    assert exp.paid?
  end
end

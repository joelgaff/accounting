require "test_helper"

class LineItemTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @ar     = Plutus::Asset.create!(tenant: @org, name: "AR")
    @sales1 = Plutus::Revenue.create!(tenant: @org, name: "Consulting")
    @sales2 = Plutus::Revenue.create!(tenant: @org, name: "Retainer")
    @tax_l  = Plutus::Liability.create!(tenant: @org, name: "Tax Payable")
    @gst    = @org.tax_rates.create!(name: "GST 10%", rate: 0.10, liability_account: @tax_l)
  end

  test "multi-line invoice posts one credit per revenue account" do
    inv = @org.invoices.create!(
      client_name: "Acme", due_date: Date.current + 30, receivable_account: @ar,
      line_items_attributes: [
        { description: "Discovery",  quantity: 1, unit_amount: 500, account_id: @sales1.id },
        { description: "Delivery",   quantity: 2, unit_amount: 750, account_id: @sales1.id },
        { description: "Retainer",   quantity: 1, unit_amount: 400, account_id: @sales2.id }
      ]
    )
    inv.reload
    assert_equal BigDecimal("2400"), inv.subtotal      # 500 + 1500 + 400
    assert_equal BigDecimal("0"),    inv.tax_amount
    assert_equal BigDecimal("2400"), inv.amount

    # Balances: AR debit 2400, Consulting credit 2000, Retainer credit 400
    assert_equal BigDecimal("2400"), @ar.balance
    assert_equal BigDecimal("2000"), @sales1.balance
    assert_equal BigDecimal("400"),  @sales2.balance
    assert_equal Plutus::DebitAmount.sum(:amount), Plutus::CreditAmount.sum(:amount)
  end

  test "mixed-tax invoice posts one liability leg per tax rate" do
    zero_tax = @org.tax_rates.create!(name: "Zero", rate: 0.0, liability_account: @tax_l)
    inv = @org.invoices.create!(
      client_name: "Acme", due_date: Date.current + 30, receivable_account: @ar,
      line_items_attributes: [
        { description: "Taxable",  quantity: 1, unit_amount: 100, account_id: @sales1.id, tax_rate_id: @gst.id },
        { description: "Exempt",   quantity: 1, unit_amount: 50,  account_id: @sales1.id, tax_rate_id: zero_tax.id }
      ]
    )
    inv.reload
    assert_equal BigDecimal("150"),  inv.subtotal
    assert_equal BigDecimal("10"),   inv.tax_amount    # only the taxable line
    assert_equal BigDecimal("160"),  inv.amount
    assert_equal BigDecimal("10"),   @tax_l.balance
  end

  test "removing a line via _destroy in nested attributes rebalances totals" do
    inv = @org.invoices.create!(
      client_name: "Acme", due_date: Date.current + 30, receivable_account: @ar,
      line_items_attributes: [
        { description: "A", quantity: 1, unit_amount: 100, account_id: @sales1.id },
        { description: "B", quantity: 1, unit_amount: 200, account_id: @sales1.id }
      ]
    )
    assert_equal BigDecimal("300"), inv.reload.amount
    assert_equal 2, inv.line_items.count
  end

  test "invoice without any line items is invalid" do
    inv = @org.invoices.build(client_name: "Bad", due_date: Date.current + 30, receivable_account: @ar)
    assert_not inv.valid?
    assert_includes inv.errors[:base].join, "line item"
  end
end

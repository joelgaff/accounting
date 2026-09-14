require "test_helper"

class Reports::AgingTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @ar    = Plutus::Asset.create!(tenant: @org, name: "AR")
    @sales = Plutus::Revenue.create!(tenant: @org, name: "Sales")
    @ap    = Plutus::Liability.create!(tenant: @org, name: "AP")
    @host  = Plutus::Expense.create!(tenant: @org, name: "Hosting")
    @org.settings.update!(payable_account: @ap)
  end

  test "AR aging buckets outstanding invoices by days past due" do
    # today
    create_invoice(@org, client_name: "Alice", amount: 100, due_date: Date.current + 10, receivable: @ar, revenue: @sales)
    # 15 days past due
    create_invoice(@org, client_name: "Bob",   amount: 200, due_date: Date.current - 15, receivable: @ar, revenue: @sales)
    # 45 days past due (Alice again — grouped by customer name)
    create_invoice(@org, client_name: "Alice", amount: 300, due_date: Date.current - 45, receivable: @ar, revenue: @sales)

    r = Reports::AccountsReceivableAging.new(organization: @org)
    alice = r.rows.find { |x| x.contact_name == "Alice" }
    bob   = r.rows.find { |x| x.contact_name == "Bob" }

    assert_equal BigDecimal("100"), alice.buckets["Current"]
    assert_equal BigDecimal("300"), alice.buckets["31-60"]
    assert_equal BigDecimal("400"), alice.total
    assert_equal BigDecimal("200"), bob.buckets["1-30"]

    assert_equal BigDecimal("100"), r.totals_by_bucket["Current"]
    assert_equal BigDecimal("600"), r.grand_total
  end

  test "AP aging buckets outstanding bills" do
    create_bill(@org, vendor: "DO",  amount: 20, category: @host, payable: @ap)                            # Current (due today+30)
    create_bill(@org, vendor: "AWS", amount: 45, category: @host, payable: @ap, date: Date.current - 60)   # ~30 days past

    r = Reports::AccountsPayableAging.new(organization: @org)
    assert_equal BigDecimal("65"), r.grand_total
  end
end

require "test_helper"

class BankAccountActivityTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @bank    = create_bank_account(@org, name: "Checking")
    @savings = create_bank_account(@org, name: "Savings", kind: "savings")
    @ar      = Plutus::Asset.create!(tenant: @org, name: "AR")
    @sales   = Plutus::Revenue.create!(tenant: @org, name: "Sales")
    @hosting = Plutus::Expense.create!(tenant: @org, name: "Hosting")
  end

  test "lists every movement on the bank with a running balance and reconciled flags" do
    inv = create_invoice(@org, client_name: "Acme", amount: 500, receivable: @ar, revenue: @sales, date: Date.new(2026, 1, 5))
    line = @org.bank_transactions.create!(bank_account: @bank, posted_on: Date.new(2026, 1, 10), amount: 500, payee: "ACME", description: "x")
    Reconciliation::MatchDocument.new(line, inv).call                                  # payment, reconciled
    create_expense(@org, vendor: "DO", amount: 30, category: @hosting, bank_account: @bank, date: Date.new(2026, 1, 12))   # unreconciled
    @org.documents.create!(date: Date.new(2026, 1, 15), total: 100, documentable: Transfer.new(from_bank_account: @bank, to_bank_account: @savings))
    @org.documents.create!(date: Date.new(2025, 12, 20), documentable: Deposit.new(bank_account: @bank),
      line_items_attributes: [ { description: "seed", quantity: 1, unit_amount: 1000, account_id: @sales.id } ])

    a = BankAccountActivity.new(@bank, from: Date.new(2026, 1, 1))
    assert_equal BigDecimal("1000"), a.opening_balance
    assert_equal [ "Invoice", "Expense", "Transfer" ], a.rows.map(&:kind)
    assert_equal [ 500, 0, 0 ].map { BigDecimal(_1) }, a.rows.map(&:received)
    assert_equal [ 0, 30, 100 ].map { BigDecimal(_1) }, a.rows.map(&:spent)
    assert_equal [ 1500, 1470, 1370 ].map { BigDecimal(_1) }, a.rows.map(&:balance)
    assert_equal [ true, false, false ], a.rows.map(&:reconciled)
    assert_equal inv, a.rows.first.document
    assert_equal 2, a.unreconciled

    all = BankAccountActivity.new(@bank)
    assert_equal 4, all.rows.size
    assert_equal BigDecimal("1370"), all.closing_balance

    savings = BankAccountActivity.new(@savings).rows.sole
    assert_equal BigDecimal("100"), savings.received
    assert_equal "Transfer", savings.kind
  end

  test "a credit card shows charges as spent and its balance as what is owed" do
    card = create_bank_account(@org, name: "Visa", kind: "credit_card")
    create_expense(@org, vendor: "Amazon", amount: 80, category: @hosting, bank_account: card)
    row = BankAccountActivity.new(card).rows.sole
    assert_equal BigDecimal("80"),  row.spent
    assert_equal BigDecimal("-80"), row.balance
  end
end

require "test_helper"

# The pages that pick or show a bank account, rendered end to end.
class BankPickersTest < ActionDispatch::IntegrationTest
  setup do
    @org = organizations(:one)
    sign_in_as_launchpad_user(@org)
    @bank = create_bank_account(@org, name: "PNC Checking", code: "1140")
    @card = create_bank_account(@org, name: "Rewards Card", code: "2068", kind: "credit_card")
    create_bank_account(@org, name: "Closed", code: "0900").archive!
    Plutus::Asset.create!(tenant: @org, name: "Accounts Receivable", code: "1200")
  end

  test "chart of accounts tags bank-backed rows with their kind" do
    get accounts_path
    assert_response :success
    assert_select "a.badge", text: "Checking"
    assert_select "a.badge", text: "Credit card"
    assert_select "td", text: /Accounts Receivable/
  end

  test "bank statement import offers only active bank accounts" do
    get new_imports_bank_path
    assert_response :success
    assert_select "select[name=bank_account_id] option", text: "1140 — PNC Checking"
    assert_select "select[name=bank_account_id] option", text: "2068 — Rewards Card"
    assert_select "select[name=bank_account_id] option", text: /Closed/, count: 0
    assert_select "select[name=bank_account_id] option", text: /Accounts Receivable/, count: 0
  end

  test "settings and payments pick from bank accounts" do
    get settings_path
    assert_response :success
    assert_select "select[name='organization_settings[bank_account_id]'] option", text: "1140 — PNC Checking"

    ar    = Plutus::Asset.find_by!(code: "1200")
    sales = Plutus::Revenue.create!(tenant: @org, name: "Sales")
    inv = create_invoice(@org, client_name: "Acme", amount: 100, receivable: ar, revenue: sales)
    get new_document_payment_path(inv)
    assert_response :success
    assert_select "select[name='payment[bank_account_id]'] option", text: "2068 — Rewards Card"

    post document_payments_path(inv), params: { payment: { amount: 100, paid_on: Date.current, bank_account_id: @card.id } }
    assert_redirected_to invoice_path(inv)
    assert_equal BigDecimal("-100"), @card.reload.balance   # a receipt debits the card, so the amount owed falls
  end
end

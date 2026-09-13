require "test_helper"

# The pages that pick or show a bank account, rendered end to end.
class BankPickersTest < ActionDispatch::IntegrationTest
  setup do
    @org = organizations(:one)
    Organization.where.not(id: @org.id).destroy_all
    payload = { sub: "u-1", email: "joel@example.com", name: "Joel", apps: [ "accounting" ],
                iat: Time.current.to_i, exp: 1.hour.from_now.to_i, iss: Ee::Jwt::ISSUER }
    cookies[Ee::Jwt::COOKIE_NAME.to_s] = ::JWT.encode(payload, Rails.application.credentials.ee_jwt_secret, "HS256")
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
    inv = @org.invoices.create!(client_name: "Acme", amount: 100, due_date: Date.current + 30,
                                receivable_account: ar, revenue_account: sales)
    get new_invoice_payment_path(inv)
    assert_response :success
    assert_select "select[name='payment[bank_account_id]'] option", text: "2068 — Rewards Card"

    post invoice_payments_path(inv), params: { payment: { amount: 100, paid_on: Date.current, bank_account_id: @card.id } }
    assert_redirected_to invoice_path(inv)
    assert_equal BigDecimal("-100"), @card.reload.balance   # a receipt debits the card, so the amount owed falls
  end
end

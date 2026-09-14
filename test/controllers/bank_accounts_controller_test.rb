require "test_helper"

class BankAccountsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @org = organizations(:one)
    sign_in_as_launchpad_user(@org)
  end

  test "lists bank accounts" do
    create_bank_account(@org, name: "PNC Checking", code: "1140")
    get bank_accounts_path
    assert_response :success
    assert_select "td", text: /PNC Checking/
  end

  test "creates a bank account together with its ledger account" do
    assert_difference [ "BankAccount.count", "Plutus::Liability.count" ], 1 do
      post bank_accounts_path, params: { bank_account: { name: "Chase United", kind: "credit_card", code: "2069", institution: "Chase", last_four: "0042" } }
    end
    assert_redirected_to bank_accounts_path
    card = @org.bank_accounts.last
    assert_equal "Chase United", card.name
    assert_equal "2069", card.code
    assert card.credit_card?
  end

  test "rejects a blank name and re-renders the form" do
    post bank_accounts_path, params: { bank_account: { name: "", kind: "checking" } }
    assert_response :unprocessable_entity
  end

  test "updates details and kind" do
    bank = create_bank_account(@org, name: "Card", kind: "checking")
    patch bank_account_path(bank), params: { bank_account: { name: "Rewards Card", kind: "credit_card", last_four: "1234" } }
    assert_redirected_to bank_accounts_path
    bank.reload
    assert_equal "Rewards Card", bank.name
    assert_kind_of Plutus::Liability, bank.account
  end

  test "archive and restore move the row between tables over turbo stream" do
    bank = create_bank_account(@org, name: "Old Bank")
    post archive_bank_account_path(bank), as: :turbo_stream
    assert_response :success
    assert bank.reload.archived?
    assert_includes response.body, ActionView::RecordIdentifier.dom_id(@org, :archived_bank_accounts)

    post restore_bank_account_path(bank), as: :turbo_stream
    assert_response :success
    assert_not bank.reload.archived?
  end
end

class BankAccountShowTest < ActionDispatch::IntegrationTest
  setup do
    @org = organizations(:one)
    sign_in_as_launchpad_user(@org)
    @bank    = create_bank_account(@org, name: "Checking")
    @hosting = Plutus::Expense.create!(tenant: @org, name: "Hosting")
  end

  test "shows the account's transactions with links to each document" do
    exp = create_expense(@org, vendor: "DigitalOcean", amount: 30, category: @hosting, bank_account: @bank)
    get bank_account_path(@bank)
    assert_response :success
    assert_select "h1", text: "Checking"
    assert_select "a[href=?]", expense_path(exp), text: "DigitalOcean"
    assert_select "td", text: "$30.00"
    assert_select "span.badge", text: "unreconciled"

    get bank_account_path(@bank, from: Date.current + 1)
    assert_select "td", text: /Nothing on this account/
    get bank_account_path(@bank, from: "", to: "")
    assert_select "a[href=?]", expense_path(exp)
  end
end

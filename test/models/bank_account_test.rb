require "test_helper"

class BankAccountTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
  end

  test "creating a checking account builds an asset ledger account tagged as a bank" do
    bank = @org.bank_accounts.create!(name: "Chase Checking", code: "1140", kind: "checking", institution: "Chase", last_four: "4821")

    assert_kind_of Plutus::Asset, bank.account
    assert_equal @org, bank.account.tenant
    assert_equal "BANK", bank.account.xero_type
    assert_equal "1140 — Chase Checking", bank.display_name
    assert_equal bank, bank.account.reload.bank_account
  end

  test "a credit card lives in liabilities" do
    card = @org.bank_accounts.create!(name: "Cash Rewards Card", kind: "credit_card")
    assert_kind_of Plutus::Liability, card.account
  end

  test "changing the kind moves the ledger account between assets and liabilities" do
    bank = @org.bank_accounts.create!(name: "Card", kind: "checking")
    Ledger.post(description: "spend", date: Date.current, commercial_document: nil,
                debits: [ { account: Plutus::Expense.create!(tenant: @org, name: "Meals"), amount: 40 } ],
                credits: [ { account: bank.account, amount: 40 } ])
    assert_equal BigDecimal("-40"), bank.balance

    bank.update!(kind: "credit_card")
    bank.reload
    assert_kind_of Plutus::Liability, bank.account
    assert_equal BigDecimal("40"), bank.balance   # now reads as an amount owed
  end

  test "validates kind and last four" do
    bank = @org.bank_accounts.build(name: "X", kind: "bitcoin", last_four: "12a")
    assert_not bank.valid?
    assert_includes bank.errors[:kind], "is not included in the list"
    assert_includes bank.errors[:last_four], "must be four digits"
  end

  test "archiving hides it from the active scope without touching the ledger" do
    bank = @org.bank_accounts.create!(name: "Old", kind: "savings")
    bank.archive!
    assert_not_includes @org.bank_accounts.active, bank
    assert_includes @org.bank_accounts.archived, bank
    assert Plutus::Account.exists?(bank.account_id)
    bank.restore!
    assert_includes @org.bank_accounts.active, bank
  end

  test "finds by ledger code or name" do
    a = @org.bank_accounts.create!(name: "Main", code: "090")
    b = @org.bank_accounts.create!(name: "Chase Business Checking")
    assert_equal a, @org.bank_accounts.find_by_code_or_name("090")
    assert_equal b, @org.bank_accounts.find_by_code_or_name("Chase Business Checking")
    assert_nil @org.bank_accounts.find_by_code_or_name("nope")
  end

  test "cannot be deleted while payments reference it" do
    bank = create_bank_account(@org, name: "Bank")
    ar    = Plutus::Asset.create!(tenant: @org, name: "AR")
    sales = Plutus::Revenue.create!(tenant: @org, name: "Sales")
    inv = create_invoice(@org, client_name: "Acme", amount: 100, receivable: ar, revenue: sales)
    inv.payments.create!(organization: @org, amount: 100, paid_on: Date.current, bank_account: bank)
    assert_not bank.destroy
  end
end

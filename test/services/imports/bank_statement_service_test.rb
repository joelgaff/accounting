require "test_helper"

class Imports::BankStatementServiceTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @bank = Plutus::Asset.create!(tenant: @org, name: "Bank")
  end

  test "imports plain-shape CSV, one row per BankTransaction, no ledger post" do
    csv = <<~CSV
      Date,Description,Amount
      2026-07-20,Client payment,250.00
      2026-07-21,Cloudflare,-8.00
    CSV
    result = Imports::BankStatementService.new(csv, bank_account: @bank, organization: @org).call

    assert_equal 2, result.imported
    assert_equal 2, BankTransaction.count
    assert_equal BigDecimal("0"), @bank.balance  # nothing posted yet
    txn = BankTransaction.find_by(amount: 250)
    assert_equal "unmatched", txn.status
  end

  test "imports Xero shape (*Date, *Amount, Payee, Description)" do
    csv = <<~CSV
      *Date,*Amount,Payee,Description,Reference
      15 Jul 2026,250.00,Acme Widgets,INV 1001,TXN-001
      16 Jul 2026,-42.50,DigitalOcean,,TXN-002
    CSV
    result = Imports::BankStatementService.new(csv, bank_account: @bank, organization: @org).call

    assert_equal 2, result.imported
    row = BankTransaction.find_by(amount: 250)
    assert_equal Date.new(2026, 7, 15), row.posted_on
    assert_equal "Acme Widgets — INV 1001", row.description
    assert_equal "TXN-001", row.reference
  end

  test "second import of same file skips duplicates" do
    csv = "Date,Description,Amount\n2026-07-20,X,100\n"
    Imports::BankStatementService.new(csv, bank_account: @bank, organization: @org).call
    result = Imports::BankStatementService.new(csv, bank_account: @bank, organization: @org).call
    assert_equal 0, result.imported
    assert_equal 1, result.duplicates
  end
end

require "test_helper"

class ChartOfAccountsImportServiceTest < ActiveSupport::TestCase
  setup { @org = organizations(:one) }

  def import(csv)
    ChartOfAccountsImportService.new(csv, organization: @org).call
  end

  test "imports a Xero-style CoA CSV mapping *Type to plutus subclasses" do
    csv = <<~CSV
      *Code,*Name,*Type,Description,*Tax Code
      090,Bank Account,BANK,,No Tax
      200,Sales,SALES,,Tax on Sales
      400,Advertising,OVERHEADS,,Tax on Purchases
      610,Accounts Receivable,CURRENT,,No Tax
      800,Accounts Payable,CURRLIAB,,No Tax
      960,Owner Capital,EQUITY,,No Tax
    CSV

    result = import(csv)
    assert_equal 6, result.created
    assert_equal 0, result.updated
    assert_equal 0, result.skipped
    assert_empty  result.errors

    scope = Plutus::Account.where(tenant: @org)
    assert_equal "Plutus::Asset",     scope.find_by(code: "090").type
    assert_equal "Plutus::Revenue",   scope.find_by(code: "200").type
    assert_equal "Plutus::Expense",   scope.find_by(code: "400").type
    assert_equal "Plutus::Liability", scope.find_by(code: "800").type
    assert_equal "Plutus::Equity",    scope.find_by(code: "960").type
  end

  test "accepts plain-English type names" do
    csv = <<~CSV
      Name,Type
      Petty Cash,Asset
      Loan,Liability
      Consulting Revenue,Income
      Meals,Expense
    CSV

    result = import(csv)
    assert_equal 4, result.created
    scope = Plutus::Account.where(tenant: @org)
    assert_equal "Plutus::Asset",     scope.find_by(name: "Petty Cash").type
    assert_equal "Plutus::Liability", scope.find_by(name: "Loan").type
    assert_equal "Plutus::Revenue",   scope.find_by(name: "Consulting Revenue").type
    assert_equal "Plutus::Expense",   scope.find_by(name: "Meals").type
  end

  test "re-import is idempotent — matches by code, updates in place" do
    csv = "*Code,*Name,*Type\n090,Bank,BANK\n"
    import(csv)

    csv2 = "*Code,*Name,*Type,Description\n090,Bank (renamed),BANK,Now with a description\n"
    result = import(csv2)
    assert_equal 0, result.created
    assert_equal 1, result.updated

    acct = Plutus::Account.where(tenant: @org, code: "090").first
    assert_equal "Bank (renamed)",         acct.name
    assert_equal "Now with a description", acct.description
  end

  test "matches an existing name-only account and attaches the code" do
    existing = Plutus::Asset.create!(tenant: @org, name: "Sales")  # deliberately wrong type
    csv = "*Code,*Name,*Type\n200,Sales,SALES\n"

    result = import(csv)
    assert_equal 0, result.created
    assert_equal 0, result.updated
    assert_equal 1, result.skipped
    assert_match(/refusing to change/, result.errors.first)
    existing.reload
    assert_equal "Plutus::Asset", existing.type
  end

  test "collects per-row errors and rejects unknown types" do
    csv = <<~CSV
      *Code,*Name,*Type
      100,Good,BANK
      101,,BANK
      102,No Type,
      103,Bad Type,MYSTERY
    CSV

    result = import(csv)
    assert_equal 1, result.created
    assert_equal 3, result.skipped
    assert_equal 3, result.errors.size
    assert(result.errors.any? { |e| e =~ /unrecognized/ })
  end

  test "reports missing required columns" do
    result = import("Foo,Bar\nx,y\n")
    assert_equal 0, result.created
    assert_match(/must have at least Name and Type/, result.errors.first)
  end

  test "handles headers with and without the Xero asterisk prefix" do
    csv = "Code,Name,Type\n100,Cash,BANK\n"
    result = import(csv)
    assert_equal 1, result.created
    assert_equal "Cash", Plutus::Account.where(tenant: @org, code: "100").first.name
  end
end

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
    assert_empty result.errors

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

  # Xero's CSV export writes display labels ("Current Liability"), not the API's
  # enum codes ("CURRLIAB"). Both spellings have to classify the same way.
  test "classifies Xero's display-label account types" do
    csv = file_fixture("xero/chart_of_accounts_labels.csv").read
    result = ChartOfAccountsImportService.new(csv, organization: @org).call

    assert_equal 19, result.created
    assert_equal 0,  result.skipped, result.errors.inspect
    assert_empty result.errors

    by_name = @org.plutus_accounts.index_by(&:name)
    {
      "Accounts Receivable"       => Plutus::Asset,
      "PNC Checking"              => Plutus::Asset,
      "Chase Business Checking"   => Plutus::Asset,
      "RDE Contract Receivable"   => Plutus::Asset,
      "Accumulated Depreciation"  => Plutus::Asset,
      "Accounts Payable"          => Plutus::Liability,
      "Deferred Gain"             => Plutus::Liability,
      "Cherryland Loans"          => Plutus::Liability,
      "Sales Tax"                 => Plutus::Liability,
      "Unpaid Expense Claims"     => Plutus::Liability,
      "Opening Balance Equity"    => Plutus::Equity,
      "Retained Earnings3"        => Plutus::Equity,
      "Historical Adjustment"     => Plutus::Equity,
      "Tracking Transfers"        => Plutus::Equity,
      "Rounding"                  => Plutus::Expense,
      "Timing Services"           => Plutus::Revenue,
      "Stripe Fees Reimbursement" => Plutus::Revenue,
      "Merch COGS"                => Plutus::Expense,
      "Travel"                    => Plutus::Expense
    }.each do |name, klass|
      assert_equal klass.name, by_name.fetch(name).type, "#{name} classified wrong"
    end
  end

  test "imports an account that has no code" do
    csv = file_fixture("xero/chart_of_accounts_labels.csv").read
    ChartOfAccountsImportService.new(csv, organization: @org).call
    assert_nil @org.plutus_accounts.find_by!(name: "Chase Business Checking").code
  end

  test "Bank rows become bank accounts, and a reclassified credit card stays a liability" do
    csv = "*Code,*Name,*Type\n1140,PNC Checking,Bank\n2068,Rewards Card,Bank\n1200,AR,Accounts Receivable\n"
    ChartOfAccountsImportService.new(csv, organization: @org).call

    checking = @org.bank_accounts.find_by_code_or_name("1140")
    card     = @org.bank_accounts.find_by_code_or_name("2068")
    assert_equal "checking", checking.kind
    assert_kind_of Plutus::Asset, checking.account
    assert_nil @org.bank_accounts.find_by_code_or_name("1200")

    card.update!(kind: "credit_card")
    result = ChartOfAccountsImportService.new(csv, organization: @org).call
    assert_empty result.errors
    assert_kind_of Plutus::Liability, Plutus::Account.find(card.account_id)
    assert_equal 2, @org.bank_accounts.count
  end
end

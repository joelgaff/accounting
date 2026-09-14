require "test_helper"

class ImportPagesTest < ActionDispatch::IntegrationTest
  setup do
    @org = organizations(:one)
    sign_in_as_launchpad_user(@org)
  end

  test "imports index lists the journal report and tax rates importers" do
    get imports_path
    assert_response :success
    assert_select "a[href=?]", new_imports_journals_path
    assert_select "a[href=?]", new_imports_tax_rates_path
  end

  test "uploading a journal report posts journal entries" do
    create_bank_account(@org, name: "Business Bank Account", code: "090")
    Plutus::Equity.create!(tenant: @org, name: "Owner's Equity", code: "300")
    Plutus::Expense.create!(tenant: @org, name: "Office Supplies", code: "400")
    Plutus::Revenue.create!(tenant: @org, name: "Sales", code: "200")
    Plutus::Liability.create!(tenant: @org, name: "Accounts Payable", code: "2000")

    get new_imports_journals_path
    assert_response :success

    post imports_journals_path, params: { file: fixture_file_upload("xero/journals.csv", "text/csv") }
    assert_redirected_to journal_entries_path
    assert_equal 4, @org.documents.journal_entries.count
    assert_match(/Created 4/, flash[:notice])
  end

  test "uploading tax rates seeds them" do
    Plutus::Liability.create!(tenant: @org, name: "Sales Tax Payable")
    Plutus::Asset.create!(tenant: @org, name: "GST Recoverable")
    post imports_tax_rates_path, params: { file: fixture_file_upload("xero/tax_rates.csv", "text/csv") }
    assert_redirected_to tax_rates_path
    assert_equal 3, @org.tax_rates.count
  end
end

require "test_helper"

class Imports::XeroJournalsServiceTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @bank    = create_bank_account(@org, name: "Business Bank Account", code: "090")
    @savings = create_bank_account(@org, name: "Savings", code: "091", kind: "savings")
    @ar      = Plutus::Asset.create!(tenant: @org, name: "Accounts Receivable", code: "1200")
    @ap      = Plutus::Liability.create!(tenant: @org, name: "Accounts Payable", code: "2000")
    @equity  = Plutus::Equity.create!(tenant: @org, name: "Owner's Equity", code: "300")
    @sales   = Plutus::Revenue.create!(tenant: @org, name: "Sales", code: "200")
    @office  = Plutus::Expense.create!(tenant: @org, name: "Office Supplies", code: "400")
  end

  def import(fixture, **opts)
    Imports::XeroJournalsService.new(file_fixture(fixture).read, organization: @org, **opts).call
  end

  def journal_by_number(n)
    JournalEntry.joins(:document).where(documents: { organization_id: @org.id }).find_by!(xero_journal_number: n).document
  end

  test "posts the report-shaped export, skipping document journals by default" do
    result = import("xero/journals.csv")

    assert_equal 4, result.created, result.errors.inspect          # conversion, spend, receive, manual
    assert_equal 5, result.skipped                                  # 3 documents + unknown account + unbalanced
    assert_equal 2, result.errors.size
    assert_match(/journal 8: account "999"/, result.errors.first)
    assert_match(/journal 9: does not balance \(off by -2\.00\)/, result.errors.last)

    conv = journal_by_number("1")
    assert_equal Date.new(2019, 1, 1), conv.date
    assert_equal "Conversion Balance: Opening balance", conv.journal_entry.narrative
    assert_equal "Conversion", conv.reference
    assert_equal "CONVERSIONBALANCE", conv.journal_entry.xero_source_type
    assert_equal BigDecimal("5000"), conv.total

    assert_equal BigDecimal("5760"), @bank.balance    # 5000 - 240 + 1000
    assert_equal BigDecimal("290"),  @office.balance  # 240 + 50
    assert_equal BigDecimal("1000"), @sales.balance
    assert_equal Plutus::DebitAmount.sum(:amount), Plutus::CreditAmount.sum(:amount)
  end

  test "documents: :include posts invoice, bill and payment journals too" do
    result = import("xero/journals.csv", documents: :include)
    assert_equal 7, result.created
    assert_equal BigDecimal("0"), @ar.balance      # invoiced 300, paid 300
    assert_equal BigDecimal("1300"), @sales.balance
  end

  test "reads the API shape with a signed NetAmount" do
    result = import("xero/journals_api.csv")
    assert_equal 2, result.created, result.errors.inspect   # spend money + transfer; ACCREC skipped
    assert_equal 1, result.skipped
    assert_equal BigDecimal("-555.5"), @bank.balance
    assert_equal BigDecimal("500"),    @savings.balance
    assert_equal "Spend money: Fuel", journal_by_number("41").journal_entry.narrative
    assert_equal "Transfer: #43",     journal_by_number("43").journal_entry.narrative
  end

  test "re-import replaces entries in place without double posting" do
    import("xero/journals.csv")
    result = import("xero/journals.csv")

    assert_equal 0, result.created
    assert_equal 4, result.updated
    assert_equal 4, @org.documents.journal_entries.count
    assert_equal BigDecimal("5760"), @bank.balance
    assert_equal 4, Plutus::Entry.where(commercial_document: @org.documents.journal_entries).count
  end

  test "rejects a file without the columns it needs" do
    result = Imports::XeroJournalsService.new("Date,Account code\n2019-01-01,090\n", organization: @org).call
    assert_equal 0, result.created
    assert_match(/Missing required columns: number, amount/, result.errors.sole)
  end
end

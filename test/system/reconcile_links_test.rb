require "application_system_test_case"

# Links inside the reconcile rows lead to whole pages, not into the frame
# the rows are streamed through.
class ReconcileLinksTest < ApplicationSystemTestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @bank    = create_bank_account(@org, name: "Checking", code: "090")
    @hosting = Plutus::Expense.create!(tenant: @org, name: "Web Hosting", code: "6820")
    @ar      = Plutus::Asset.create!(tenant: @org, name: "AR", code: "1200")
    @sales   = Plutus::Revenue.create!(tenant: @org, name: "Sales", code: "4100")
    @org.settings.update!(receivable_account: @ar)
    sign_in_as_launchpad_user(@org)
  end

  test "Make a rule opens the rule form prefilled from the line" do
    txn = @org.bank_transactions.create!(bank_account: @bank, posted_on: Date.current, amount: -48, payee: "Blue Pixel Hosting", description: "BLUEPIXEL HOSTING 10/02")
    visit "/bank_transactions"
    within("##{ActionView::RecordIdentifier.dom_id(txn)}") do
      click_on "Expense"
      click_on "Make a rule"
    end
    assert_current_path new_bank_rule_path(bank_transaction_id: txn.id)
    assert_selector "h1", text: /rule/i
    assert_field "bank_rule[pattern]", with: "Blue Pixel Hosting"
  end

  test "a matched line's document link opens the document" do
    inv = create_invoice(@org, client_name: "Northwind", amount: 500, receivable: @ar, revenue: @sales)
    txn = @org.bank_transactions.create!(bank_account: @bank, posted_on: Date.current, amount: 500, payee: "Northwind", description: "ACH")
    Reconciliation::MatchDocument.new(txn, inv).call
    visit "/bank_transactions?status=matched"
    within("##{ActionView::RecordIdentifier.dom_id(txn)}") { click_on inv.label, match: :first }
    assert_current_path invoice_path(inv)
    assert_selector "h1", text: inv.label
  end
end

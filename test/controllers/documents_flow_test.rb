require "test_helper"

# Creating each document type through its controller, and settling one.
class DocumentsFlowTest < ActionDispatch::IntegrationTest
  setup do
    @org = organizations(:one)
    sign_in_as_launchpad_user(@org)
    @bank    = create_bank_account(@org, name: "Bank", code: "090")
    @ar      = Plutus::Asset.create!(tenant: @org, name: "Accounts Receivable", code: "1200")
    @ap      = Plutus::Liability.create!(tenant: @org, name: "Accounts Payable", code: "2000")
    @sales   = Plutus::Revenue.create!(tenant: @org, name: "Sales", code: "200")
    @hosting = Plutus::Expense.create!(tenant: @org, name: "Hosting", code: "400")
    @org.settings.update!(receivable_account: @ar, payable_account: @ap)
  end

  def line(amount, account) = { "0" => { description: "Line", quantity: 1, unit_amount: amount, account_id: account.id } }

  test "creates an invoice with a line item and posts it when approved" do
    post invoices_path, params: { document: { date: "2026-09-01", documentable_attributes: { client_name: "Acme", due_date: "2026-10-01" },
                                              line_items_attributes: line(500, @sales) }, approve: "1" }
    assert_redirected_to invoices_path
    doc = @org.documents.invoices.sole
    assert_equal BigDecimal("500"), doc.total
    assert_equal "Acme", doc.invoice.client_name
    assert_equal BigDecimal("500"), @ar.balance
    get invoice_path(doc)
    assert_response :success
    assert_select "h1", text: doc.label
  end

  test "creates a bill accrued to AP and a payment against it" do
    post bills_path, params: { document: { date: "2026-09-01", documentable_attributes: { vendor: "AWS" },
                                           line_items_attributes: line(45, @hosting) }, approve: "1" }
    assert_redirected_to bills_path
    bill = @org.documents.bills.sole
    assert_equal BigDecimal("45"), @ap.balance

    get new_document_payment_path(bill)
    assert_response :success
    post document_payments_path(bill), params: { payment: { amount: 45, paid_on: "2026-09-02", bank_account_id: @bank.id } }
    assert_redirected_to bill_path(bill)
    assert bill.reload.paid?
    assert_equal BigDecimal("-45"), @bank.balance
  end

  test "creates an expense paid from a bank" do
    post expenses_path, params: { document: { date: "2026-09-01", documentable_attributes: { vendor: "DO", bank_account_id: @bank.id },
                                              line_items_attributes: line(20, @hosting) } }
    assert_redirected_to expenses_path
    assert_equal BigDecimal("-20"), @bank.balance
    get expenses_path
    assert_response :success
    assert_select "td", text: "DO"
  end

  test "creates a journal entry from nested lines" do
    post journal_entries_path, params: { document: { date: "2026-09-01", documentable_attributes: {
      narrative: "Adjust", lines_attributes: { "0" => { account_id: @hosting.id, debit_amount: 10 }, "1" => { account_id: @bank.account.id, credit_amount: 10 } } } } }
    doc = @org.documents.journal_entries.sole
    assert_redirected_to journal_entry_path(doc)
    assert_equal BigDecimal("10"), doc.total
    get journal_entry_path(doc)
    assert_response :success
  end

  test "re-renders the form with the type's errors" do
    post invoices_path, params: { document: { date: "2026-09-01", documentable_attributes: {}, line_items_attributes: line(5, @sales) } }
    assert_response :unprocessable_entity
    assert_match(/Client name can(?:&#39;|')t be blank/, response.body)
  end

  test "reconcile matches a deposit to an invoice and categorizes a withdrawal" do
    inv = create_invoice(@org, client_name: "Acme", amount: 100, receivable: @ar, revenue: @sales)
    dep = @org.bank_transactions.create!(bank_account: @bank, posted_on: Date.current, amount: 100, description: "ACME PAYMENT")
    wd  = @org.bank_transactions.create!(bank_account: @bank, posted_on: Date.current, amount: -30, description: "HOSTING CO")

    get bank_transactions_path
    assert_response :success

    post match_bank_transaction_path(dep), params: { document_id: inv.id }, as: :turbo_stream
    assert_response :success
    assert inv.reload.paid?
    assert_equal "matched", dep.reload.status

    post categorize_bank_transaction_path(wd), params: { account_id: @hosting.id }, as: :turbo_stream
    assert_response :success
    exp = @org.documents.expenses.sole
    assert_equal BigDecimal("30"), exp.total
    assert_equal exp, wd.reload.document
    assert_equal Plutus::DebitAmount.sum(:amount), Plutus::CreditAmount.sum(:amount)
  end

  test "every document page renders" do
    inv  = create_invoice(@org, client_name: "Acme", amount: 100, receivable: @ar, revenue: @sales)
    bill = create_bill(@org, vendor: "AWS", amount: 45, category: @hosting, payable: @ap)
    exp  = create_expense(@org, vendor: "DO", amount: 20, category: @hosting, bank_account: @bank)
    je   = @org.documents.create!(date: Date.current, documentable: JournalEntry.new(
      narrative: "Adjust", lines_attributes: [ { account_id: @hosting.id, debit_amount: 5 }, { account_id: @bank.account.id, credit_amount: 5 } ]))
    inv.payments.create!(organization: @org, amount: 40, paid_on: Date.current, bank_account: @bank)
    @org.settings.update!(receivable_account: @ar, payable_account: @ap, bank_account: @bank)

    [ invoices_path, invoice_path(inv), print_invoice_path(inv), email_invoice_path(inv), new_invoice_path,
      bills_path, bill_path(bill), new_bill_path,
      expenses_path, expense_path(exp), new_expense_path,
      journal_entries_path, journal_entry_path(je), new_journal_entry_path,
      root_path, contacts_path, imports_path,
      reports_accounts_receivable_aging_path, reports_accounts_payable_aging_path, reports_general_ledger_path ].each do |path|
      get path
      assert_response :success, "#{path} failed: #{response.status}"
    end
  end

  test "creates a deposit and a transfer through their pages" do
    savings = create_bank_account(@org, name: "Savings", code: "091", kind: "savings")
    post deposits_path, params: { document: { date: "2026-09-01", documentable_attributes: { bank_account_id: @bank.id },
                                              line_items_attributes: line(250, @sales) } }
    assert_redirected_to deposits_path
    assert_equal BigDecimal("250"), @bank.balance

    post transfers_path, params: { document: { date: "2026-09-02", total: 100, documentable_attributes: { from_bank_account_id: @bank.id, to_bank_account_id: savings.id } } }
    assert_redirected_to transfers_path
    assert_equal BigDecimal("150"), @bank.balance
    assert_equal BigDecimal("100"), savings.balance

    [ deposits_path, deposit_path(@org.documents.deposits.sole), new_deposit_path,
      transfers_path, transfer_path(@org.documents.transfers.sole), new_transfer_path ].each do |path|
      get path
      assert_response :success, "#{path} failed: #{response.status}"
    end
  end
end

class DashboardLinksTest < ActionDispatch::IntegrationTest
  test "recent activity rows link to the document behind each entry" do
    org = organizations(:one)
    sign_in_as_launchpad_user(org)
    ar    = Plutus::Asset.create!(tenant: org, name: "AR")
    sales = Plutus::Revenue.create!(tenant: org, name: "Sales")
    bank  = create_bank_account(org, name: "Checking")
    inv = create_invoice(org, client_name: "Acme", amount: 300, receivable: ar, revenue: sales)
    inv.payments.create!(organization: org, amount: 300, paid_on: Date.current, bank_account: bank)

    org.settings.update!(bank_account: bank, receivable_account: ar)

    get root_path
    assert_response :success
    assert_select "td a[href=?]", invoice_path(inv), minimum: 3, text: /Invoice|Payment/
    assert_select "a.kpi-card[href=?]", bank_account_path(bank)
    assert_select "a.kpi-card[href=?]", reports_accounts_receivable_aging_path
    assert_select "article.kpi-card", text: /Accounts Payable/, count: 1
  end
end

class BrandingTest < ActionDispatch::IntegrationTest
  test "the product name comes from configuration and is never split" do
    org = organizations(:one)
    sign_in_as_launchpad_user(org)
    get root_path
    assert_select "title", text: "Partita Doppia"
    assert_select "meta[name=application-name][content=?]", "Partita Doppia"
    assert_select ".tb-name", text: "Partita Doppia"
    assert_select ".nav-footer strong", text: "Partita Doppia"
    assert_select ".app-statusbar", text: /Partita Doppia/
    assert_no_match(/LEDGER|>Ledger</, response.body)

    get pwa_manifest_path(format: :json)
    assert_response :success
    assert_equal "Partita Doppia", response.parsed_body["name"]
    assert_equal "Partita Doppia", response.parsed_body["short_name"]
  end
end

class LaunchpadAppKeyTest < ActionDispatch::IntegrationTest
  test "the hub may name this app by its new key or the old one, and nothing else" do
    org = organizations(:one)
    Organization.where.not(id: org.id).destroy_all
    { "partita_doppia" => :success, "accounting" => :success, "vendors" => :forbidden }.each do |key, expected|
      payload = { sub: "u-#{org.id}", email: "joel@example.com", name: "Joel", apps: [ key ], iat: Time.current.to_i, exp: 1.hour.from_now.to_i, iss: Ee::Jwt.issuer }
      cookies[Ee::Jwt::COOKIE_NAME.to_s] = ::JWT.encode(payload, Rails.application.credentials.ee_jwt_secret, "HS256")
      get root_path
      assert_response expected, "apps: #{key}"
    end
  end
end

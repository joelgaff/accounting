require "test_helper"

# Invoices and bills start as drafts; approving is a deliberate click.
class DraftFlowTest < ActionDispatch::IntegrationTest
  setup do
    @org = organizations(:one)
    sign_in_as_launchpad_user(@org)
    @ar      = Plutus::Asset.create!(tenant: @org, name: "AR", code: "1200")
    @ap      = Plutus::Liability.create!(tenant: @org, name: "AP", code: "2000")
    @sales   = Plutus::Revenue.create!(tenant: @org, name: "Sales", code: "200")
    @hosting = Plutus::Expense.create!(tenant: @org, name: "Hosting", code: "400")
  end

  def line(amount, account) = { "0" => { description: "Line", quantity: 1, unit_amount: amount, account_id: account.id } }
  def invoice_params(**extra) = { document: { date: "2026-09-01", documentable_attributes: { client_name: "Acme", due_date: "2026-10-01", receivable_account_id: @ar.id }, line_items_attributes: line(500, @sales) }, **extra }
  def bill_params(**extra)    = { document: { date: "2026-09-01", documentable_attributes: { vendor: "AWS", payable_account_id: @ap.id }, line_items_attributes: line(45, @hosting) }, **extra }
  def status_id(doc) = ActionView::RecordIdentifier.dom_id(doc, :status)

  test "a new invoice is a draft with a number and no posting" do
    get new_invoice_path
    assert_select "input[type=submit][value='Save draft']"
    assert_select "input[type=submit][value='Approve']"

    post invoices_path, params: invoice_params
    doc = @org.documents.invoices.sole
    assert doc.draft?
    assert_match(/\AINV-\d+\z/, doc.invoice.number)
    assert_equal 0, doc.entries.count
    assert_equal BigDecimal("0"), @ar.balance

    get invoice_path(doc)
    assert_select "span.badge-draft", text: "draft"
    assert_select "form[action=?] button", approve_invoice_path(doc), text: "Approve"
  end

  test "approving on create posts straight away" do
    post invoices_path, params: invoice_params(approve: "1")
    doc = @org.documents.invoices.sole
    assert doc.approved?
    assert_equal 1, doc.entries.count
    assert_equal BigDecimal("500"), @ar.balance
  end

  test "approving from the show page streams the status header" do
    doc = create_invoice(@org, client_name: "Acme", amount: 500, receivable: @ar, revenue: @sales, state: "draft")
    post approve_invoice_path(doc), as: :turbo_stream
    assert_response :success
    assert_match(/target="#{status_id(doc)}"/, response.body)
    assert_match(/badge-open/, response.body)
    assert doc.reload.approved?
    assert_equal 1, doc.entries.count
  end

  test "a draft can be edited and approved in the same save" do
    doc = create_invoice(@org, client_name: "Acme", amount: 500, receivable: @ar, revenue: @sales, state: "draft")
    get edit_invoice_path(doc)
    assert_select "input[type=submit][value='Save draft']"
    patch invoice_path(doc), params: { document: { reference: "Q-1", line_items_attributes: { "0" => { id: doc.line_items.sole.id, unit_amount: 750 } } } }
    assert doc.reload.draft?
    assert_equal BigDecimal("750"), doc.total
    assert_equal 0, doc.entries.count

    patch invoice_path(doc), params: { document: { reference: "Q-2" }, approve: "1" }
    assert doc.reload.approved?
    assert_equal "Q-2", doc.reference
    assert_equal BigDecimal("750"), @ar.balance
  end

  test "an approved invoice's edit form has one submit and no approve" do
    doc = create_invoice(@org, client_name: "Acme", amount: 500, receivable: @ar, revenue: @sales)
    get edit_invoice_path(doc)
    assert_select "input[type=submit][value='Update invoice']"
    assert_select "input[type=submit][value='Approve']", 0
  end

  test "the index filters on draft and the print view says so" do
    draft = create_invoice(@org, client_name: "Acme", amount: 500, receivable: @ar, revenue: @sales, state: "draft")
    real  = create_invoice(@org, client_name: "Acme", amount: 100, receivable: @ar, revenue: @sales)
    get invoices_path(status: "draft")
    assert_select "tr##{ActionView::RecordIdentifier.dom_id(draft)}", 1
    assert_select "tr##{ActionView::RecordIdentifier.dom_id(real)}", 0

    get print_invoice_path(draft)
    assert_select ".doc", text: /DRAFT/
    get print_invoice_path(real)
    assert_select ".doc", text: /DRAFT/, count: 0

    assert_equal "DRAFT INVOICE", InvoicePdf.new(draft).title
    assert_equal "INVOICE",       InvoicePdf.new(real).title
    get print_invoice_path(draft, format: :pdf)
    assert_response :success
  end

  test "bills draft and approve the same way" do
    post bills_path, params: bill_params
    doc = @org.documents.bills.sole
    assert doc.draft?
    assert_equal BigDecimal("0"), @ap.balance

    post approve_bill_path(doc), as: :turbo_stream
    assert_response :success
    assert doc.reload.approved?
    assert_equal BigDecimal("45"), @ap.balance

    get bills_path(status: "draft")
    assert_select "tr##{ActionView::RecordIdentifier.dom_id(doc)}", 0
  end

  test "a draft cannot be emailed" do
    doc = create_invoice(@org, client_name: "Acme", amount: 500, receivable: @ar, revenue: @sales, state: "draft")
    get invoice_path(doc)
    assert_select "a[href=?]", email_invoice_path(doc), 0

    get email_invoice_path(doc)
    assert_redirected_to invoice_path(doc)
    assert_match(/draft/i, flash[:alert])

    assert_no_enqueued_emails do
      post send_email_invoice_path(doc), params: { to: "billing@acme.example" }
    end
    assert_redirected_to invoice_path(doc)
    assert_equal 0, doc.events.where(action: "emailed").count
  end

  test "other types are approved on create, as before" do
    bank = create_bank_account(@org, name: "Bank", code: "090")
    post expenses_path, params: { document: { date: "2026-09-01", documentable_attributes: { vendor: "DO", bank_account_id: bank.id }, line_items_attributes: line(20, @hosting) } }
    doc = @org.documents.expenses.sole
    assert doc.approved?
    assert_equal 1, doc.entries.count
  end
end

require "test_helper"

class DocumentEditingTest < ActionDispatch::IntegrationTest
  setup do
    @org = organizations(:one)
    sign_in_as_launchpad_user(@org)
    @bank    = create_bank_account(@org, name: "Bank", code: "090")
    @ar      = Plutus::Asset.create!(tenant: @org, name: "AR", code: "1200")
    @ap      = Plutus::Liability.create!(tenant: @org, name: "AP", code: "2000")
    @sales   = Plutus::Revenue.create!(tenant: @org, name: "Sales", code: "200")
    @hosting = Plutus::Expense.create!(tenant: @org, name: "Hosting", code: "400")
  end

  def status_id(doc) = ActionView::RecordIdentifier.dom_id(doc, :status)

  test "edit and update an invoice reposts the ledger" do
    inv  = create_invoice(@org, client_name: "Acme", amount: 500, receivable: @ar, revenue: @sales)
    line = inv.line_items.sole
    get edit_invoice_path(inv)
    assert_response :success
    assert_select "input[value='Update invoice']"

    patch invoice_path(inv), params: { document: { reference: "R-9", documentable_attributes: { client_name: "Acme Ltd" },
                                                  line_items_attributes: { "0" => { id: line.id, unit_amount: 750, quantity: 1, description: "x", account_id: @sales.id } } } }
    assert_redirected_to invoice_path(inv)
    inv.reload
    assert_equal "Acme Ltd", inv.invoice.client_name
    assert_equal BigDecimal("750"), inv.total
    assert_equal BigDecimal("750"), @ar.balance
    assert_equal 1, inv.entries.count
  end

  test "update failures re-render the edit form" do
    inv = create_invoice(@org, client_name: "Acme", amount: 500, receivable: @ar, revenue: @sales)
    inv.payments.create!(organization: @org, amount: 400, paid_on: Date.current, bank_account: @bank)
    patch invoice_path(inv), params: { document: { line_items_attributes: { "0" => { id: inv.line_items.sole.id, unit_amount: 100 } } } }
    assert_response :unprocessable_entity
    assert_match(/already paid/, response.body)
  end

  test "void streams the status header and the payments section" do
    inv = create_invoice(@org, client_name: "Acme", amount: 500, receivable: @ar, revenue: @sales)
    inv.payments.create!(organization: @org, amount: 100, paid_on: Date.current, bank_account: @bank)
    post void_invoice_path(inv), as: :turbo_stream
    assert_response :success
    assert_match(/target="#{status_id(inv)}"/, response.body)
    assert_match(/badge-voided/, response.body)
    assert inv.reload.voided?
    assert_equal 0, inv.payments.count

    get edit_invoice_path(inv)
    assert_redirected_to invoice_path(inv)
    get invoices_path
    assert_select "tr##{ActionView::RecordIdentifier.dom_id(inv)}", 0
    get invoices_path(status: "voided")
    assert_select "tr##{ActionView::RecordIdentifier.dom_id(inv)}", 1
  end

  test "each other type has edit, update and void" do
    savings = create_bank_account(@org, name: "Savings", code: "091", kind: "savings")
    bill = create_bill(@org, vendor: "AWS", amount: 45, category: @hosting, payable: @ap)
    exp  = create_expense(@org, vendor: "DO", amount: 20, category: @hosting, bank_account: @bank)
    dep  = @org.documents.create!(date: Date.current, documentable: Deposit.new(bank_account: @bank),
                                  line_items_attributes: [ { description: "d", quantity: 1, unit_amount: 9, account_id: @sales.id } ])
    tr   = @org.documents.create!(date: Date.current, total: 100, documentable: Transfer.new(from_bank_account: @bank, to_bank_account: savings))
    je   = @org.documents.create!(date: Date.current, documentable: JournalEntry.new(narrative: "Adj",
             lines_attributes: [ { account_id: @hosting.id, debit_amount: 5 }, { account_id: @bank.account.id, credit_amount: 5 } ]))

    { bill => :bill, exp => :expense, dep => :deposit, tr => :transfer, je => :journal_entry }.each do |doc, name|
      get public_send("edit_#{name}_path", doc)
      assert_response :success, "edit #{name}"
      patch public_send("#{name}_path", doc), params: { document: { reference: "ref-#{name}" } }
      assert_redirected_to public_send("#{name}_path", doc)
      assert_equal "ref-#{name}", doc.reload.reference
      post public_send("void_#{name}_path", doc), as: :turbo_stream
      assert_response :success, "void #{name}"
      assert doc.reload.voided?
    end
    assert_equal 0, Plutus::Entry.count
  end

  test "updating a journal entry replaces its lines" do
    je = @org.documents.create!(date: Date.current, documentable: JournalEntry.new(narrative: "Adj",
           lines_attributes: [ { account_id: @hosting.id, debit_amount: 5 }, { account_id: @bank.account.id, credit_amount: 5 } ]))
    l1, l2 = je.journal_entry.lines.to_a
    patch journal_entry_path(je), params: { document: { documentable_attributes: { narrative: "Bigger",
      lines_attributes: { "0" => { id: l1.id, account_id: @hosting.id, debit_amount: 8 }, "1" => { id: l2.id, account_id: @bank.account.id, credit_amount: 8 } } } } }
    assert_redirected_to journal_entry_path(je)
    assert_equal BigDecimal("8"), je.reload.total
    assert_equal BigDecimal("8"), @hosting.balance
  end

  test "removing a payment streams the sections and frees the bank line" do
    inv = create_invoice(@org, client_name: "Acme", amount: 500, receivable: @ar, revenue: @sales)
    txn = @org.bank_transactions.create!(bank_account: @bank, posted_on: Date.current, amount: 500, description: "ACME")
    post match_bank_transaction_path(txn), params: { document_id: inv.id }, as: :turbo_stream
    payment = inv.payments.sole
    delete payment_path(payment), as: :turbo_stream
    assert_response :success
    assert_match(/target="#{status_id(inv)}"/, response.body)
    assert_match(/target="#{ActionView::RecordIdentifier.dom_id(inv, :payments)}"/, response.body)
    assert_not Payment.exists?(payment.id)
    assert txn.reload.unmatched?
    assert_equal "open", inv.reload.status
  end

  test "contact page lists activity and the mailer renders line items" do
    contact = @org.contacts.create!(name: "Acme", kind: "customer", email: "a@acme.example")
    inv = create_invoice(@org, contact: contact, amount: 500, receivable: @ar, revenue: @sales)
    get contact_path(contact)
    assert_response :success
    assert_select "td", text: inv.label
    assert_match(/500\.00 outstanding/, response.body)

    mail = InvoiceMailer.send_invoice(inv, to: "a@acme.example")
    assert_match(/Services rendered/, mail.html_part.body.encoded)
    assert_match(/Balance due/, mail.text_part.body.encoded)
  end

  test "indexes paginate" do
    60.times { |i| @org.bank_transactions.create!(bank_account: @bank, posted_on: Date.current, amount: 1, description: "L#{i}") }
    get bank_transactions_path
    assert_select "tbody tr", 60
    120.times { |i| @org.bank_transactions.create!(bank_account: @bank, posted_on: Date.current, amount: 2, description: "M#{i}") }
    get bank_transactions_path
    assert_select "tbody tr", 100
    assert_select "a", text: "Older →"
    get bank_transactions_path(page: 2)
    assert_select "tbody tr", 80
  end
end

class DocumentHistoryPagesTest < ActionDispatch::IntegrationTest
  setup do
    @org = organizations(:one)
    sign_in_as_launchpad_user(@org)
    @ar    = Plutus::Asset.create!(tenant: @org, name: "AR")
    @sales = Plutus::Revenue.create!(tenant: @org, name: "Sales")
    @invoice = create_invoice(@org, client_name: "Acme", amount: 500, receivable: @ar, revenue: @sales)
  end

  test "show pages list history, notes append over turbo stream, and emailing records the send" do
    get invoice_path(@invoice)
    assert_response :success
    assert_select "section h2", text: "History & notes"
    assert_select "li.history-event strong", text: "Created"

    post document_notes_path(@invoice), params: { note: { text: "Chased by phone" } }, as: :turbo_stream
    assert_response :success
    assert_match(/Chased by phone/, response.body)
    assert_equal "note", @invoice.events.newest_first.first.action
    assert_equal "Joel", @invoice.events.newest_first.first.actor_name

    assert_enqueued_emails 1 do
      post send_email_invoice_path(@invoice), params: { to: "ap@acme.example", subject: "Your invoice" }
    end
    assert_redirected_to invoice_path(@invoice)
    emailed = @invoice.events.newest_first.first
    assert_equal "emailed", emailed.action
    assert_equal "ap@acme.example", emailed.details["to"]

    get print_invoice_path(@invoice, format: :pdf)
    assert_response :success
    assert_equal "application/pdf", response.media_type
    assert response.body.start_with?("%PDF-")
  end
end

require "test_helper"

# "Copy" on an invoice or bill opens the new form filled from it; nothing is
# saved until the form is. The new document's history says where it came from.
class CopyDocumentTest < ActionDispatch::IntegrationTest
  setup do
    @org = organizations(:one)
    sign_in_as_launchpad_user(@org)
    @ar      = Plutus::Asset.create!(tenant: @org, name: "AR", code: "1200")
    @ap      = Plutus::Liability.create!(tenant: @org, name: "AP", code: "2000")
    @sales   = Plutus::Revenue.create!(tenant: @org, name: "Sales", code: "200")
    @hosting = Plutus::Expense.create!(tenant: @org, name: "Hosting", code: "400")
    @org.settings.update!(receivable_account: @ar, payable_account: @ap)
    @customer = @org.contacts.create!(name: "Acme", kind: "customer")
    @original = create_invoice(@org, contact: @customer, amount: 500, receivable: @ar, revenue: @sales,
                               date: Date.new(2026, 1, 10), due_date: Date.new(2026, 2, 9), reference: "PO 4471")
  end

  test "an invoice offers Copy, which opens the new form filled from it without saving anything" do
    get invoice_path(@original)
    assert_select "a[href=?]", copy_invoice_path(@original), text: "Copy"

    assert_no_difference -> { Document.count } do
      get copy_invoice_path(@original)
    end
    assert_response :success
    assert_select "h1", "New invoice"
    assert_select "form[action=?]", invoices_path
    assert_select "select[name='document[contact_id]'] option[selected][value=?]", @customer.id.to_s
    assert_select "input[name='document[documentable_attributes][client_name]'][value=?]", "Acme"
    assert_select "input[name='document[date]'][value=?]", Date.current.iso8601
    assert_select "input[name='document[documentable_attributes][due_date]'][value=?]", (Date.current + 30).iso8601
    assert_select "input[name='document[documentable_attributes][number]']" do |inputs|
      assert_not_equal @original.invoice.number, inputs.first["value"], "a fresh number"
    end
    assert_select "input[name='document[reference]'][value]", 0, "the reference stays with the original"
    assert_select "input[name*='[line_items_attributes]'][name$='[description]'][value=?]", "Services rendered"
    assert_select "tbody[data-line-items-target=rows] input[name$='[unit_amount]']" do |inputs|
      assert_equal [ 500 ], inputs.map { |i| i["value"].to_d }
    end
    assert_select "input[name*='[line_items_attributes]'][name$='[id]']", 0, "copied lines are new, not the original's"
    assert_select "input[type=hidden][name='document[copied_from_id]'][value=?]", @original.id.to_s
    assert_select "input[type=submit][value='Save draft']"
    assert_match(/Copied from #{Regexp.escape(@original.label)}/, response.body)
  end

  test "saving the copy records where it came from" do
    post invoices_path, params: { document: {
      date: Date.current.iso8601, contact_id: @customer.id, copied_from_id: @original.id,
      documentable_attributes: { client_name: "Acme", due_date: (Date.current + 30).iso8601 },
      line_items_attributes: { "0" => { description: "Services rendered", quantity: 1, unit_amount: 500, account_id: @sales.id } }
    } }
    copy = @org.documents.invoices.order(:id).last
    assert_not_equal @original, copy
    assert copy.draft?
    get invoice_path(copy)
    assert_match(/Copied from #{Regexp.escape(@original.label)}/, response.body)
    assert_select "a[href=?]", invoice_path(@original)
  end

  test "a copied_from_id that is not one of ours records nothing" do
    post invoices_path, params: { document: {
      date: Date.current.iso8601, contact_id: @customer.id, copied_from_id: 999_999,
      documentable_attributes: { client_name: "Acme", due_date: (Date.current + 30).iso8601 },
      line_items_attributes: { "0" => { description: "x", quantity: 1, unit_amount: 5, account_id: @sales.id } }
    } }
    copy = @org.documents.invoices.order(:id).last
    assert_nil copy.events.find_by!(action: "created").details["copied_from"]
  end

  test "a bill offers Copy too" do
    bill = create_bill(@org, vendor: "AWS", amount: 45, category: @hosting, payable: @ap)
    get bill_path(bill)
    assert_select "a[href=?]", copy_bill_path(bill), text: "Copy"
    get copy_bill_path(bill)
    assert_response :success
    assert_select "h1", "New bill"
    assert_select "input[name='document[documentable_attributes][vendor]'][value=?]", "AWS"
    assert_select "tbody[data-line-items-target=rows] input[name$='[unit_amount]']" do |inputs|
      assert_equal [ 45 ], inputs.map { |i| i["value"].to_d }
    end
    assert_select "input[type=hidden][name='document[copied_from_id]'][value=?]", bill.id.to_s
  end
end

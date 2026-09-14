require "test_helper"

class TrackingPagesTest < ActionDispatch::IntegrationTest
  setup do
    @org = organizations(:one)
    sign_in_as_launchpad_user(@org)
    @ar    = Plutus::Asset.create!(tenant: @org, name: "AR")
    @sales = Plutus::Revenue.create!(tenant: @org, name: "Sales")
  end

  test "manage categories under settings and tag a line from the invoice form" do
    get tracking_categories_path
    assert_response :success
    post tracking_categories_path, params: { tracking_category: { name: "Event Year", active: "1", options_attributes: { "0" => { name: "2026", active: "1" }, "1" => { name: "", active: "1" } } } }
    assert_redirected_to tracking_categories_path
    cat = @org.tracking_categories.sole
    assert_equal [ "2026" ], cat.options.pluck(:name)

    get new_invoice_path
    assert_response :success
    assert_select "th", text: "Event Year"
    assert_select "select[name='document[line_items_attributes][0][tracking_option_ids][]']"

    post invoices_path, params: { document: { date: "2026-09-01", documentable_attributes: { client_name: "Acme", due_date: "2026-10-01", receivable_account_id: @ar.id },
      line_items_attributes: { "0" => { description: "x", quantity: 1, unit_amount: 100, account_id: @sales.id, tracking_option_ids: [ cat.options.first.id ] } } } }
    inv = @org.documents.invoices.sole
    assert_equal "2026", inv.line_items.sole.tracking_option_for(cat).name
    get invoice_path(inv)
    assert_select "td", text: "2026"

    get reports_profit_and_loss_by_tracking_path(tracking_category_id: cat.id)
    assert_response :success
    assert_select "th", text: "2026"
    assert_select "th", text: "Unassigned"

    patch tracking_category_path(cat), params: { tracking_category: { name: "Event Year", active: "0" } }
    assert_redirected_to tracking_categories_path
    delete tracking_category_path(cat)
    assert_redirected_to tracking_categories_path
    assert TrackingCategory.exists?(cat.id), "in use, so refused"
  end
end

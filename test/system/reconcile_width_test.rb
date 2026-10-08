require "application_system_test_case"

# A suggestion with long names and several chips must not widen the page: the
# text ellipsises, the chips wrap, and OK stays on screen.
class ReconcileWidthTest < ApplicationSystemTestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @bank  = create_bank_account(@org, name: "Chase United MileagePlus", code: "2069", kind: "credit_card")
    @subs  = Plutus::Expense.create!(tenant: @org, name: "Internet:Web Hosting and Service subscriptions", code: "6602")
    klass  = @org.tracking_categories.create!(name: "Class")
    year   = @org.tracking_categories.create!(name: "Event Year")
    @ee    = klass.options.create!(name: "Endurance Evolution Timing Services")
    @y     = year.options.create!(name: "2026")
    sign_in_as_launchpad_user(@org)
  end

  test "a long suggestion with chips keeps the page inside the viewport and OK on screen" do
    3.times do |i|
      t = @org.bank_transactions.create!(bank_account: @bank, posted_on: Date.new(2026, 7 + i, 1), amount: -80, payee: "IONOS / 1and1 Internet Inc", description: "IONOS Inc. K193262374/005")
      Reconciliation::Categorize.new(t, account: @subs, contact_name: "IONOS / 1and1 Internet Inc", tracking_option_ids: [ @ee.id, @y.id ]).call
    end
    fresh = @org.bank_transactions.create!(bank_account: @bank, posted_on: Date.current, amount: -80, payee: "IONOS / 1and1 Internet Inc", description: "IONOS Inc. K193262374/005")

    [ DESKTOP, [ 1100, 800 ], PHONE ].each do |w, h|
      resize_to(w, h)
      visit "/bank_transactions?status=unmatched"
      row = find("##{ActionView::RecordIdentifier.dom_id(fresh)}")
      main_scroll, main_client = page.evaluate_script("[document.querySelector('.app-main').scrollWidth, document.querySelector('.app-main').clientWidth]")
      assert main_scroll <= main_client, "at #{w}px the main area scrolls sideways: #{main_scroll} in #{main_client}"
      assert_fits_viewport("reconcile at #{w}")
      within(row) do
        assert_selector ".suggestion .coding-tracking", text: "2026", visible: true
        ok = find(".suggestion .btn", text: "OK")
        right = page.evaluate_script("arguments[0].getBoundingClientRect().right", ok.native)
        assert_operator right, :<=, w, "at #{w}px OK sits off the right edge"
      end
    end
  end
end

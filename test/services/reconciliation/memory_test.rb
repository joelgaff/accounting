require "test_helper"

# What the books remember about a payee: how its lines were coded before.
class Reconciliation::MemoryTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @checking = create_bank_account(@org, name: "Checking")
    @hosting  = Plutus::Expense.create!(tenant: @org, name: "Web Hosting")
    @software = Plutus::Expense.create!(tenant: @org, name: "Software")
    @sales    = Plutus::Revenue.create!(tenant: @org, name: "Sales")
    @tax      = @org.tax_rates.create!(name: "Sales Tax", rate: 0.0875, liability_account: Plutus::Liability.create!(tenant: @org, name: "Tax"))
    @klass    = @org.tracking_categories.create!(name: "Class")
    @timing   = @klass.options.create!(name: "Timing")
  end

  def line(amount, description, on: Date.current)
    @org.bank_transactions.create!(bank_account: @checking, posted_on: on, amount: amount, description: description)
  end

  # A line reconciled by hand into an expense, the way Categorize does it.
  def coded(description, account:, on:, tax: nil, tracking: [], contact: "Blue Pixel Hosting", amount: -48)
    txn = line(amount, description, on: on)
    Reconciliation::Categorize.new(txn, account: account, tax_rate: tax, contact_name: contact, tracking_option_ids: tracking).call
    txn
  end

  test "three agreeing codings make a payee confident; the newest contact, tax and tracking come along" do
    coded("BLUEPIXEL HOSTING 07/02", account: @hosting, on: Date.new(2026, 7, 2), tracking: [ @timing.id ])
    coded("BLUEPIXEL HOSTING 08/02", account: @hosting, on: Date.new(2026, 8, 2), tracking: [ @timing.id ])
    coded("BLUEPIXEL HOSTING 09/02", account: @hosting, on: Date.new(2026, 9, 2), tracking: [ @timing.id ], tax: @tax)
    fresh = line(-48, "BLUEPIXEL HOSTING 10/02")

    hit = Reconciliation::Memory.new(@org, [ fresh ]).for(fresh)
    assert hit.confident?
    assert_equal 3, hit.count
    assert_equal @hosting, hit.account
    assert_equal "Blue Pixel Hosting", hit.contact_name
    assert_equal [ @timing.id ], hit.tracking_option_ids
    assert_nil hit.tax_rate, "tax differs across the three, so none is assumed"
  end

  test "fewer than three, or disagreement, is a hint carrying the most recent coding" do
    coded("AMZN MKTP US*2K3", account: @hosting,  on: Date.new(2026, 8, 1), contact: "Amazon")
    coded("AMZN MKTP US*7Q9", account: @software, on: Date.new(2026, 9, 1), contact: "Amazon")
    coded("AMZN MKTP US*9Z1", account: @software, on: Date.new(2026, 9, 15), contact: "Amazon")
    fresh = line(-20, "AMZN MKTP US*1A1")

    hit = Reconciliation::Memory.new(@org, [ fresh ]).for(fresh)
    assert_not hit.confident?
    assert_equal @software, hit.account, "the most recent coding leads"
    assert_equal 3, hit.count

    coded("GUSTO PAYROLL 09/26", account: @hosting, on: Date.new(2026, 9, 26), contact: "Gusto", amount: -6459)
    gusto = line(-6459, "GUSTO PAYROLL 10/10")
    assert_not Reconciliation::Memory.new(@org, [ gusto ]).for(gusto).confident?
  end

  test "memory respects direction and ignores voided documents and unknown payees" do
    coded("SQ *SUMMIT RACES", account: @hosting, on: Date.new(2026, 9, 1), contact: "Summit Races")
    deposit = line(500, "SQ *SUMMIT RACES")
    assert_nil Reconciliation::Memory.new(@org, [ deposit ]).for(deposit), "money in never borrows an expense coding"

    void_me = coded("ZOOM.US 888-799-9666", account: @software, on: Date.new(2026, 9, 1), contact: "Zoom")
    void_me.document.void!
    zoom = line(-15, "ZOOM.US 888-799-9666")
    assert_nil Reconciliation::Memory.new(@org, [ zoom ]).for(zoom)

    stranger = line(-9, "NEW VENDOR 1234")
    assert_nil Reconciliation::Memory.new(@org, [ stranger ]).for(stranger)
  end

  test "an expense typed by hand teaches the same lesson when its vendor is in the line" do
    create_expense(@org, vendor: "Gusto", amount: 6459, category: @hosting, bank_account: @checking, date: Date.new(2026, 7, 1))
    create_expense(@org, vendor: "Gusto", amount: 6459, category: @hosting, bank_account: @checking, date: Date.new(2026, 8, 1))
    create_expense(@org, vendor: "Gusto", amount: 6459, category: @hosting, bank_account: @checking, date: Date.new(2026, 9, 1))
    fresh = line(-6459, "GUSTO PAYROLL 10/10")

    hit = Reconciliation::Memory.new(@org, [ fresh ]).for(fresh)
    assert hit.confident?
    assert_equal @hosting, hit.account
    assert_equal "Gusto", hit.contact_name
  end
end

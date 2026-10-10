require "test_helper"

# An expense or bill can be flagged as billable to a customer: a cost to be
# picked up on that customer's next invoice. Other document kinds can't.
class BillableDocumentTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @ar      = Plutus::Asset.create!(tenant: @org, name: "AR", code: "1200")
    @ap      = Plutus::Liability.create!(tenant: @org, name: "AP", code: "2000")
    @sales   = Plutus::Revenue.create!(tenant: @org, name: "Sales", code: "4100")
    @travel  = Plutus::Expense.create!(tenant: @org, name: "Travel", code: "6812")
    @bank    = create_bank_account(@org, name: "Checking")
    @org.settings.update!(receivable_account: @ar, payable_account: @ap, bank_account: @bank)
    @northwind = @org.contacts.create!(name: "Northwind", kind: "customer")
    @delta     = @org.contacts.create!(name: "Delta", kind: "vendor")
  end

  test "an expense and a bill can be billable to a customer; the scope finds what is flagged for them" do
    ticket = create_expense(@org, vendor: "Delta", amount: 500, category: @travel, bank_account: @bank, billable_to: @northwind)
    hotel  = create_bill(@org, vendor: "Marriott", amount: 300, category: @travel, payable: @ap, billable_to: @northwind)
    create_expense(@org, vendor: "Zoom", amount: 15, category: @travel, bank_account: @bank)
    assert_equal @northwind, ticket.reload.billable_to
    assert_equal [ hotel, ticket ].sort, @org.documents.billable_to(@northwind).sort
    assert_empty @org.documents.billable_to(@delta)
  end

  test "a voided expense and a draft bill are not offered" do
    ticket = create_expense(@org, vendor: "Delta", amount: 500, category: @travel, bank_account: @bank, billable_to: @northwind)
    draft  = create_bill(@org, vendor: "Marriott", amount: 300, category: @travel, payable: @ap, billable_to: @northwind, state: "draft")
    assert_equal [ ticket ], @org.documents.billable_to(@northwind).to_a
    ticket.void!
    assert_empty @org.documents.billable_to(@northwind)
    draft.approve!
    assert_equal [ draft ], @org.documents.billable_to(@northwind).to_a
  end

  test "only purchases can be billable, and only to one of our contacts" do
    inv = create_invoice(@org, client_name: "Acme", amount: 100, receivable: @ar, revenue: @sales)
    inv.billable_to = @northwind
    assert_not inv.valid?
    assert inv.errors[:billable_to].any?

    stranger = Organization.create!(name: "Other").contacts.create!(name: "Theirs", kind: "customer")
    exp = @org.documents.build(date: Date.current, contact: @delta, documentable: Expense.new(bank_account: @bank), billable_to: stranger,
                               line_items_attributes: [ { description: "x", quantity: 1, unit_amount: 5, account_id: @travel.id } ])
    assert_not exp.valid?
    assert exp.errors[:billable_to].any?
  end

  test "flagging a cost to a vendor-only contact makes them a customer too" do
    create_expense(@org, vendor: "Zoom", amount: 15, category: @travel, bank_account: @bank, billable_to: @delta)
    assert_equal "both", @delta.reload.kind
  end

  test "a copy is a new cost: the flag does not come across" do
    ticket = create_expense(@org, vendor: "Delta", amount: 500, category: @travel, bank_account: @bank, billable_to: @northwind)
    copy = @org.documents.build(date: Date.current, documentable: Expense.new(bank_account: @bank)).copy_from(ticket)
    assert_nil copy.billable_to
  end
end

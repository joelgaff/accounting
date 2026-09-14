require "test_helper"

class BankRuleTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @bank    = create_bank_account(@org, name: "Checking")
    @hosting = Plutus::Expense.create!(tenant: @org, name: "Hosting")
  end

  def line(amount, payee: "", description: "LINE", bank: @bank)
    @org.bank_transactions.new(organization: @org, bank_account: bank, posted_on: Date.current, amount: amount, payee: payee, description: description)
  end

  def rule(**attrs)
    @org.bank_rules.create!({ name: "r", match_kind: "contains", pattern: "cloudflare", amount_sign: "any", action_kind: "Expense", account: @hosting }.merge(attrs))
  end

  test "contains, starts_with and regex match case-insensitively over payee and description" do
    assert rule.matches?(line(-8, payee: "CLOUDFLARE INC"))
    assert rule.matches?(line(-8, description: "pos purchase cloudflare"))
    assert_not rule.matches?(line(-8, description: "AWS"))
    assert rule(match_kind: "starts_with", pattern: "sq *").matches?(line(-8, description: "SQ *COFFEE"))
    assert_not rule(match_kind: "starts_with", pattern: "coffee").matches?(line(-8, description: "SQ *COFFEE"))
    assert rule(match_kind: "regex", pattern: "gusto|payroll").matches?(line(-8, payee: "GUSTO"))
  end

  test "direction and bank account narrow a rule" do
    assert_not rule(amount_sign: "in").matches?(line(-8, payee: "cloudflare"))
    assert rule(amount_sign: "out").matches?(line(-8, payee: "cloudflare"))
    other = create_bank_account(@org, name: "Savings", kind: "savings")
    assert_not rule(bank_account: other).matches?(line(-8, payee: "cloudflare"))
  end

  test "a bad regex is rejected, and a slow one fails closed" do
    r = @org.bank_rules.build(name: "x", match_kind: "regex", pattern: "(", action_kind: "Expense", account: @hosting)
    assert_not r.valid?
    assert_includes r.errors[:pattern].join, "regex"
    slow = rule(match_kind: "regex", pattern: "(a+)+$")
    assert_not slow.matches?(line(-8, description: "a" * 40 + "!"))
  end

  test "an action needs a target" do
    assert_not @org.bank_rules.build(name: "x", pattern: "p", action_kind: "Expense").valid?
    assert_not @org.bank_rules.build(name: "x", pattern: "p", action_kind: "Transfer").valid?
    assert @org.bank_rules.build(name: "x", pattern: "p", action_kind: "Transfer", transfer_bank_account: @bank).valid?
  end

  test "apply! categorizes or transfers" do
    savings = create_bank_account(@org, name: "Savings", kind: "savings")
    l1 = line(-8, payee: "CLOUDFLARE").tap(&:save!)
    rule(contact: @org.contacts.create!(name: "Cloudflare", kind: "vendor")).apply!(l1)
    assert l1.reload.matched?
    assert_equal "Cloudflare", l1.document.contact.name
    l2 = line(-100, payee: "TRANSFER TO SAVINGS").tap(&:save!)
    rule(pattern: "savings", action_kind: "Transfer", account: nil, transfer_bank_account: savings).apply!(l2)
    assert l2.reload.document.transfer?
  end
end

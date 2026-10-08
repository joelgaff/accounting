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
    assert_includes r.errors.full_messages.join, "regex"
    slow = rule(match_kind: "regex", pattern: "(a+)+$")
    assert_not slow.matches?(line(-8, description: "a" * 40 + "!"))
  end

  test "an action needs a target" do
    assert_not @org.bank_rules.build(name: "x", pattern: "p", action_kind: "Expense").valid?
    assert_not @org.bank_rules.build(name: "x", pattern: "p", action_kind: "Transfer").valid?
    assert @org.bank_rules.build(name: "x", pattern: "p", action_kind: "Transfer", transfer_bank_account: @bank).valid?
  end

  # ── Several conditions on one rule ─────────────────────────────────────────

  def conditioned(match_all: true, **attrs)
    @org.bank_rules.create!({ name: "r", amount_sign: "any", action_kind: "Expense", account: @hosting, match_all: match_all,
                              conditions_attributes: [ { field: "text", operator: "contains", value: "lyft" },
                                                       { field: "amount", operator: "more_than", value: "20" } ] }.merge(attrs))
  end

  test "a rule holds when all its conditions hold, or when any does, as asked" do
    all = conditioned
    assert all.matches?(line(-25, payee: "LYFT *RIDE"))
    assert_not all.matches?(line(-10, payee: "LYFT *RIDE")), "amount fails"
    assert_not all.matches?(line(-25, payee: "UBER")), "text fails"

    any = conditioned(match_all: false)
    assert any.matches?(line(-10, payee: "LYFT *RIDE"))
    assert any.matches?(line(-25, payee: "UBER"))
    assert_not any.matches?(line(-10, payee: "UBER"))
  end

  test "amount conditions compare the size of the amount, whichever way the money went" do
    more = @org.bank_rules.create!(name: "big", amount_sign: "any", action_kind: "Expense", account: @hosting,
                                    conditions_attributes: [ { field: "amount", operator: "more_than", value: "1000" } ])
    assert more.matches?(line(-1500))
    assert more.matches?(line(1500))
    assert_not more.matches?(line(-999.99))

    between = @org.bank_rules.create!(name: "mid", amount_sign: "any", action_kind: "Expense", account: @hosting,
                                       conditions_attributes: [ { field: "amount", operator: "between", value: "10", value_to: "20" } ])
    assert between.matches?(line(-15))
    assert between.matches?(line(-20))
    assert_not between.matches?(line(-20.01))

    exact = @org.bank_rules.create!(name: "exact", amount_sign: "out", action_kind: "Expense", account: @hosting,
                                     conditions_attributes: [ { field: "amount", operator: "equals", value: "14.99" } ])
    assert exact.matches?(line(-14.99))
    assert_not exact.matches?(line(14.99)), "direction is still the rule's scope"
  end

  test "a condition can look at one field alone" do
    payee = @org.bank_rules.create!(name: "p", amount_sign: "any", action_kind: "Expense", account: @hosting,
                                     conditions_attributes: [ { field: "payee", operator: "contains", value: "gusto" } ])
    assert payee.matches?(line(-8, payee: "GUSTO", description: "ACH"))
    assert_not payee.matches?(line(-8, payee: "ACH", description: "GUSTO"))

    ref = @org.bank_rules.create!(name: "ref", amount_sign: "any", action_kind: "Expense", account: @hosting,
                                   conditions_attributes: [ { field: "reference", operator: "equals", value: "INV-7" } ])
    l = line(-8); l.reference = "inv-7"
    assert ref.matches?(l)
  end

  test "a rule needs at least one condition, and operators must suit their field" do
    none = @org.bank_rules.build(name: "x", amount_sign: "any", action_kind: "Expense", account: @hosting)
    assert_not none.valid?
    assert_includes none.errors[:conditions].join, "at least one"

    bad = @org.bank_rules.build(name: "x", amount_sign: "any", action_kind: "Expense", account: @hosting,
                                conditions_attributes: [ { field: "amount", operator: "contains", value: "5" } ])
    assert_not bad.valid?
    bad2 = @org.bank_rules.build(name: "x", amount_sign: "any", action_kind: "Expense", account: @hosting,
                                 conditions_attributes: [ { field: "payee", operator: "more_than", value: "5" } ])
    assert_not bad2.valid?
    nan = @org.bank_rules.build(name: "x", amount_sign: "any", action_kind: "Expense", account: @hosting,
                                conditions_attributes: [ { field: "amount", operator: "more_than", value: "lots" } ])
    assert_not nan.valid?
  end

  test "pattern and match_kind still build the rule's first condition" do
    r = rule(match_kind: "starts_with", pattern: "sq *")
    assert_equal [ [ "text", "starts_with", "sq *" ] ], r.conditions.map { |c| [ c.field, c.operator, c.value ] }
  end

  test "the summary spells the conditions out" do
    assert_equal "payee or description contains “lyft” and amount more than 20.00", conditioned.when_summary
    assert_equal "payee or description contains “lyft” or amount more than 20.00", conditioned(match_all: false).when_summary
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

require "test_helper"

# The key that says two statement lines are "the same payee": what the bank
# prints minus the parts that change from one charge to the next.
class Reconciliation::PayeeKeyTest < ActiveSupport::TestCase
  SAME = [
    [ "AMZN Mktp US*2K3", "AMZN MKTP US*7Q9", "amzn mktp us" ],
    [ "BLUEPIXEL HOSTING 10/02", "BLUEPIXEL HOSTING 09/02", "bluepixel hosting" ],
    [ "GUSTO PAYROLL 09/26", "Gusto Payroll 10/10", "gusto payroll" ],
    [ "SQ *SUMMIT RACES", "SQ *SUMMIT RACES #4471", "sq summit races" ],
    [ "Xero Inv XERO US INV-7876814", "Xero Inv XERO US INV-7876902", "xero inv xero us inv" ],
    [ "Chase Credit Crd Autopay  PPD ID: 4760039224", "CHASE CREDIT CRD AUTOPAY PPD ID: 4760039991", "chase crd autopay" ]
  ].freeze

  test "charges from the same payee share a key" do
    SAME.each do |a, b, key|
      assert_equal key, Reconciliation::PayeeKey.for(a), a
      assert_equal key, Reconciliation::PayeeKey.for(b), b
    end
  end

  test "words that describe the transaction, not the payee, never make a key on their own" do
    [ "CHECK 1234", "Check #1250", "ATM WITHDRAWAL 10/02", "MOBILE DEPOSIT", "ONLINE PAYMENT", "ZELLE PAYMENT", "ONLINE PAYMENT TO CARD 0042",
      "DEBIT CARD PURCHASE", "ACH CREDIT", "WIRE TRANSFER FEE", "POS DEBIT", "INTEREST PAYMENT" ].each do |text|
      assert_nil Reconciliation::PayeeKey.for(text), text
    end
  end

  test "those words still drop out when a payee is there too" do
    assert_equal "landlord llc", Reconciliation::PayeeKey.for("CHECK 1234 LANDLORD LLC")
    assert_equal "northwind trail", Reconciliation::PayeeKey.for("ACH CREDIT NORTHWIND TRAIL")
    assert_equal "summit races", Reconciliation::PayeeKey.for("ZELLE PAYMENT TO SUMMIT RACES")
  end

  test "too little text is no key at all" do
    assert_nil Reconciliation::PayeeKey.for("")
    assert_nil Reconciliation::PayeeKey.for(nil)
    assert_nil Reconciliation::PayeeKey.for("4471")
    assert_nil Reconciliation::PayeeKey.for("PMT")
  end

  test "a statement line is keyed by its payee, falling back to its description" do
    org  = organizations(:one)
    bank = create_bank_account(org, name: "Checking")
    with_payee = org.bank_transactions.create!(bank_account: bank, posted_on: Date.current, amount: -5, payee: "Blue Pixel Hosting", description: "BLUEPIXEL HOSTING 10/02")
    without    = org.bank_transactions.create!(bank_account: bank, posted_on: Date.current, amount: -5, description: "BLUEPIXEL HOSTING 10/02")
    assert_equal "blue pixel hosting", Reconciliation::PayeeKey.for_line(with_payee)
    assert_equal "bluepixel hosting",  Reconciliation::PayeeKey.for_line(without)
  end
end

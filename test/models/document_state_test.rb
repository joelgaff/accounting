require "test_helper"

class DocumentStateTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @ar    = Plutus::Asset.create!(tenant: @org, name: "AR")
    @sales = Plutus::Revenue.create!(tenant: @org, name: "Sales")
  end

  test "a document is draft or approved, nothing else, and approved unless told otherwise" do
    doc = create_invoice(@org, client_name: "Acme", amount: 10, receivable: @ar, revenue: @sales)
    assert_equal "approved", doc.state
    assert doc.approved?
    assert_not doc.draft?

    doc.state = "bogus"
    assert_not doc.valid?
    assert_includes doc.errors[:state].join, "not included"
  end
end

require "test_helper"

class Imports::OfxParserTest < ActiveSupport::TestCase
  test "SGML and XML statements read the same" do
    sgml = Imports::OfxParser.parse(file_fixture("ofx/checking_sgml.qfx").read)
    xml  = Imports::OfxParser.parse(file_fixture("ofx/checking_xml.ofx").read)
    [ sgml, xml ].each do |st|
      assert_equal "000000004821", st.account_id
      assert_equal "checking", st.account_kind
      assert_equal "USD", st.currency
      assert_equal BigDecimal("4321.55"), st.ledger_balance
      assert_equal Date.new(2026, 9, 10), st.balance_at
      assert_equal 3, st.rows.size
      assert_equal({ external_id: "2026090201", posted_on: Date.new(2026, 9, 2), amount: BigDecimal("-8"), payee: "CLOUDFLARE INC",
                     description: "POS PURCHASE CLOUDFLARE", reference: nil, type: "DEBIT" }, st.rows[0])
      assert_equal "ACME WIDGETS & CO", st.rows[1][:payee]
      assert_equal "ACME WIDGETS & CO", st.rows[1][:description]   # memo falls back to name
      assert_equal "1042", st.rows[2][:reference]
    end
  end

  test "credit card statements, comma decimals and Windows-1252 bytes" do
    st = Imports::OfxParser.parse(file_fixture("ofx/creditcard_sgml.qfx").binread)
    assert_equal "credit_card", st.account_kind
    assert_equal "4111111111112068", st.account_id
    assert_equal BigDecimal("-42.5"), st.rows[0][:amount]
    assert_match(/H.TZNER/, st.rows[0][:payee])
    assert_equal BigDecimal("-1200"), st.ledger_balance
  end

  test "refuses files that are not OFX" do
    assert_raises(Imports::OfxParser::ParseError) { Imports::OfxParser.parse("Date,Amount\n2026-01-01,5\n") }
  end
end

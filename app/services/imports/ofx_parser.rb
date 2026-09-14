module Imports
  # Reads OFX 1.x (SGML, leaves unclosed) and 2.x (XML) bank and card
  # statements, which is what banks hand out as .ofx / .qfx downloads.
  # Aggregates close their tags in both dialects; only leaves differ, and the
  # leaf pattern stops at the next tag or line end so both shapes read alike.
  class OfxParser
    class ParseError < StandardError; end

    Statement = Struct.new(:account_id, :account_kind, :currency, :ledger_balance, :balance_at, :rows, keyword_init: true)

    def self.parse(source)
      new(source).statement
    end

    def initialize(source)
      raw   = (source.respond_to?(:read) ? source.read : source.to_s).b
      text  = raw.dup.force_encoding("UTF-8")
      text  = raw.encode("UTF-8", "Windows-1252", invalid: :replace, undef: :replace) unless text.valid_encoding?
      @body = text[/<OFX>.*/mi] or raise ParseError, "No <OFX> block found — is this an OFX/QFX file?"
    end

    def statement
      account = aggregate("BANKACCTFROM") || aggregate("CCACCTFROM")
      balance = aggregate("LEDGERBAL")
      rows    = @body.scan(%r{<STMTTRN>(.*?)</STMTTRN>}mi).map { |(chunk)| row(chunk) }
      raise ParseError, "No transactions or account found in the file" if rows.empty? && account.nil?

      Statement.new(
        account_id:     leaf(account, "ACCTID"),
        account_kind:   @body.match?(/<CCACCTFROM>/i) ? "credit_card" : leaf(account, "ACCTTYPE")&.downcase,
        currency:       leaf(@body, "CURDEF"),
        ledger_balance: balance && amount(leaf(balance, "BALAMT")),
        balance_at:     balance && date(leaf(balance, "DTASOF")),
        rows:           rows
      )
    end

    private

    def aggregate(tag)
      @body[%r{<#{tag}>(.*?)</#{tag}>}mi, 1]
    end

    # <TAG>value            (SGML)   or   <TAG>value</TAG>   (XML)
    def leaf(chunk, tag)
      return nil if chunk.nil?
      value = chunk[/<#{tag}>([^<\r\n]*)/i, 1]
      value && CGI.unescapeHTML(value.strip).presence
    end

    def row(chunk)
      {
        external_id: leaf(chunk, "FITID"),
        posted_on:   date(leaf(chunk, "DTPOSTED")),
        amount:      amount(leaf(chunk, "TRNAMT")),
        payee:       leaf(chunk, "NAME") || leaf(chunk, "PAYEE").to_s,
        description: leaf(chunk, "MEMO") || leaf(chunk, "NAME").to_s,
        reference:   leaf(chunk, "CHECKNUM") || leaf(chunk, "REFNUM"),
        type:        leaf(chunk, "TRNTYPE")
      }
    end

    # "20260910120000.000[-5:EST]" → 2026-09-10
    def date(value)
      raise ParseError, "missing date" if value.blank?
      Date.strptime(value[0, 8], "%Y%m%d")
    rescue ArgumentError
      raise ParseError, "unreadable date #{value.inspect}"
    end

    def amount(value)
      raise ParseError, "missing amount" if value.blank?
      BigDecimal(value.include?(".") ? value : value.tr(",", "."))
    rescue ArgumentError
      raise ParseError, "unreadable amount #{value.inspect}"
    end
  end
end

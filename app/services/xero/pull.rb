require "csv"

module Xero
  # Reads Xero's API and writes each collection as the CSV the file importers
  # already understand, so an API import and a bundle import are the same
  # code path with the same idempotency. Tracking comes through on every
  # line, which the CSV exports can't always give.
  class Pull
    LIVE_INVOICE_STATUSES = %w[AUTHORISED PAID].freeze

    def initialize(client)
      @client = client
    end

    def tracking_categories = @client.get("TrackingCategories", key: "TrackingCategories")

    def accounts
      @accounts ||= @client.get("Accounts", key: "Accounts").reject { |a| a["Status"] == "ARCHIVED" }
    end

    def chart_csv
      csv(%w[Code Name Type TaxType Description]) do |out|
        accounts.each { |a| out << [ a["Code"], a["Name"], a["Type"], a["TaxType"], a["Description"] ] }
      end
    end

    # Sales tax collected goes to Xero's tax control account (SystemAccount
    # GST, whatever it is called); purchase tax stays unrecoverable here.
    def tax_rates_csv
      control = accounts.find { |a| a["SystemAccount"] == "GST" }
      csv(%w[Name TaxType Rate LiabilityAccount]) do |out|
        @client.get("TaxRates", key: "TaxRates").each do |t|
          next if t["Status"] == "DELETED" || t["Status"] == "ARCHIVED"
          liability = control && t["TaxType"].to_s.start_with?("OUTPUT") ? (control["Code"].presence || control["Name"]) : nil
          out << [ t["Name"], t["TaxType"], t["EffectiveRate"], liability ]
        end
      end
    end

    # [customers_csv, vendors_csv, both_csv]: a contact Xero marks as both, or
    # as neither, lands in the third so it keeps both roles here.
    def contacts_csvs
      contacts = @client.each_page("Contacts", key: "Contacts").reject { |c| c["ContactStatus"] == "ARCHIVED" }
      headers  = %w[ContactName EmailAddress FirstName LastName POAddressLine1 POAddressLine2 POCity PORegion POPostalCode POCountry PhoneNumber TaxNumber]
      split = ->(keep) { csv(headers) { |out| contacts.select(&keep).each { |c| out << contact_row(c) } } }
      [ split.(->(c) { c["IsCustomer"] && !c["IsSupplier"] }),
        split.(->(c) { c["IsSupplier"] && !c["IsCustomer"] }),
        split.(->(c) { !!c["IsCustomer"] == !!c["IsSupplier"] }) ]
    end

    INVOICE_HEADERS = %w[ContactName EmailAddress InvoiceNumber Reference InvoiceDate DueDate Description Quantity UnitAmount
                         AccountCode TaxType TrackingName1 TrackingOption1 TrackingName2 TrackingOption2
                         AmountPaid FullyPaidOnDate BankAccount].freeze
    BILL_HEADERS    = (INVOICE_HEADERS + %w[InvoiceID]).freeze

    # type: "ACCREC" (sales invoices) or "ACCPAY" (bills), issued on or after from.
    def invoices_csv(type, from: nil)
      clauses = [ %(Type=="#{type}") ]
      clauses << %(Date>=DateTime(#{from.year},#{from.month},#{from.day})) if from
      params = { where: clauses.join("&&") }
      bills = type == "ACCPAY"
      csv(bills ? BILL_HEADERS : INVOICE_HEADERS) do |out|
        @client.each_page("Invoices", params, key: "Invoices").each do |inv|
          next unless LIVE_INVOICE_STATUSES.include?(inv["Status"])
          number = inv["InvoiceNumber"].presence || ("XERO-#{inv['InvoiceID'].to_s[0, 8]}" unless bills)
          paid_from = bank_code_for(inv)
          rows = []
          Array(inv["LineItems"]).each do |li|
            next if li["AccountCode"].blank?
            qty, unit = net_quantity_and_unit(li, inv["LineAmountTypes"])
            t1, t2 = Array(li["Tracking"]).first(2)
            row = [ inv.dig("Contact", "Name"), inv.dig("Contact", "EmailAddress"), number, inv["Reference"],
                    date(inv["DateString"] || inv["Date"]), date(inv["DueDateString"] || inv["DueDate"]),
                    li["Description"].presence || "Line", qty, unit,
                    li["AccountCode"], li["TaxType"], t1&.dig("Name"), t1&.dig("Option"), t2&.dig("Name"), t2&.dig("Option"),
                    inv["AmountPaid"], date(inv["FullyPaidOnDate"]), paid_from ]
            row << inv["InvoiceID"] if bills
            rows << row
          end
          settle_drift!(rows, inv["SubTotal"], qty_at: 7, unit_at: 8).each { |row| out << row }
        end
      end
    end

    BANK_TXN_HEADERS = %w[Type BankTransactionID Date ContactName Reference BankAccount Description Quantity UnitAmount
                          AccountCode TaxType TrackingName1 TrackingOption1 TrackingName2 TrackingOption2].freeze

    # Spend and receive money, one row per line, unit amounts net of tax.
    # Transfers, prepayments and overpayments are other things and are skipped here.
    def bank_transactions_csv(from: nil)
      params = from ? { where: %(Date>=DateTime(#{from.year},#{from.month},#{from.day})) } : {}
      csv(BANK_TXN_HEADERS) do |out|
        @client.each_page("BankTransactions", params, key: "BankTransactions").each do |t|
          next unless t["Status"] == "AUTHORISED" && %w[SPEND RECEIVE].include?(t["Type"])
          bank  = t.dig("BankAccount", "Code").presence || t.dig("BankAccount", "Name")
          lines = Array(t["LineItems"]).reject { |li| li["AccountCode"].blank? }
          # Xero lets a receive go negative (a refund out) and a spend go
          # negative (money back in); here that is simply the other kind.
          type  = t["Type"]
          if BigDecimal(t["Total"].to_s.presence || "0").negative?
            type  = type == "SPEND" ? "RECEIVE" : "SPEND"
            lines = lines.map { |li| li.merge("LineAmount" => -BigDecimal(li["LineAmount"].to_s.presence || "0"), "UnitAmount" => -BigDecimal(li["UnitAmount"].to_s.presence || "0"), "TaxAmount" => -BigDecimal(li["TaxAmount"].to_s.presence || "0")) }
          end
          rows = lines.map do |li|
            qty, unit = net_quantity_and_unit(li, t["LineAmountTypes"])
            t1, t2 = Array(li["Tracking"]).first(2)
            [ type, t["BankTransactionID"], date(t["DateString"] || t["Date"]), t.dig("Contact", "Name"), t["Reference"], bank,
              li["Description"].presence || t["Reference"].presence || "Line", qty, unit, li["AccountCode"], li["TaxType"],
              t1&.dig("Name"), t1&.dig("Option"), t2&.dig("Name"), t2&.dig("Option") ]
          end
          settle_drift!(rows, t["SubTotal"], qty_at: 7, unit_at: 8).each { |row| out << row }
        end
      end
    end

    def bank_transfers_csv(from: nil)
      params = from ? { where: %(Date>=DateTime(#{from.year},#{from.month},#{from.day})) } : {}
      csv(%w[BankTransferID Date Amount FromBankAccount ToBankAccount]) do |out|
        @client.get("BankTransfers", params, key: "BankTransfers").each do |t|
          out << [ t["BankTransferID"], date(t["Date"]), t["Amount"],
                   t.dig("FromBankAccount", "Code").presence || t.dig("FromBankAccount", "Name"),
                   t.dig("ToBankAccount", "Code").presence   || t.dig("ToBankAccount", "Name") ]
        end
      end
    end

    JOURNAL_HEADERS = %w[JournalDate JournalNumber SourceType Reference Description AccountCode NetAmount TaxType
                         TrackingName1 TrackingOption1 TrackingName2 TrackingOption2].freeze

    # Posted manual journals in the journal importer's shape; a positive
    # LineAmount is a debit.
    def manual_journals_csv(from: nil)
      params = from ? { where: %(Date>=DateTime(#{from.year},#{from.month},#{from.day})) } : {}
      csv(JOURNAL_HEADERS) do |out|
        @client.each_page("ManualJournals", params, key: "ManualJournals").each do |j|
          next unless j["Status"] == "POSTED"
          Array(j["JournalLines"]).each do |line|
            t1, t2 = Array(line["Tracking"]).first(2)
            out << [ date(j["Date"]), "MJ-#{j['ManualJournalID']}", "MANJOURNAL", j["Narration"], line["Description"].presence || j["Narration"],
                     line["AccountCode"], line["LineAmount"], line["TaxType"],
                     t1&.dig("Name"), t1&.dig("Option"), t2&.dig("Name"), t2&.dig("Option") ]
          end
        end
      end
    end

    private

    def csv(headers)
      CSV.generate { |out| out << headers; yield out }
    end

    def date(value) = Client.parse_date(value)&.iso8601

    # Xero totals its lines before rounding them, so a document's subtotal can
    # sit a few cents away from the sum of its rounded lines. Put the
    # difference on the last line (as one unit at the adjusted net) so the
    # document lands on Xero's subtotal and settles in full.
    def settle_drift!(rows, subtotal, qty_at:, unit_at:)
      return rows if rows.empty? || subtotal.nil?
      wanted = BigDecimal(subtotal.to_s)
      have   = rows.sum { |r| (BigDecimal(r[qty_at].to_s) * BigDecimal(r[unit_at].to_s)).round(2) }
      drift  = wanted - have
      return rows if drift.zero? || drift.abs > [ BigDecimal("1"), wanted.abs * BigDecimal("0.01") ].max   # anything bigger is not rounding
      last = rows.last
      net  = (BigDecimal(last[qty_at].to_s) * BigDecimal(last[unit_at].to_s)).round(2) + drift
      last[qty_at], last[unit_at] = "1", net.to_s("F")
      rows
    end

    # Our lines are quantity × net unit price with tax on top. Keep Xero's
    # quantity and unit when they multiply out to the net exactly; otherwise
    # one line at the net amount, so totals land to the cent.
    def net_quantity_and_unit(li, line_amount_types)
      qty   = BigDecimal(li["Quantity"].to_s.presence || "1")
      unit  = BigDecimal(li["UnitAmount"].to_s.presence || "0")
      gross = li["LineAmount"].nil? ? (qty * unit).round(2) : BigDecimal(li["LineAmount"].to_s)
      tax   = BigDecimal(li["TaxAmount"].to_s.presence || "0")
      net   = line_amount_types == "Inclusive" ? gross - tax : gross
      (qty * unit).round(2) == net ? [ qty.to_s("F"), unit.to_s("F") ] : [ "1", net.to_s("F") ]
    end

    def contact_row(c)
      addr = Array(c["Addresses"]).find { |a| a["AddressType"] == "POBOX" } || Array(c["Addresses"]).first || {}
      phone = Array(c["Phones"]).find { |p| p["PhoneType"] == "DEFAULT" && p["PhoneNumber"].present? } || {}
      [ c["Name"], c["EmailAddress"], c["FirstName"], c["LastName"], addr["AddressLine1"], addr["AddressLine2"], addr["City"],
        addr["Region"], addr["PostalCode"], addr["Country"], phone["PhoneNumber"], c["TaxNumber"] ]
    end

    # The chart code of the bank account the invoice's last payment hit, from
    # the Payments collection (the invoice's own payment list omits the account).
    def bank_code_for(invoice)
      payments_by_invoice[invoice["InvoiceID"]]
    end

    def payments_by_invoice
      @payments_by_invoice ||= @client.each_page("Payments", key: "Payments")
        .reject { |p| p["Status"] == "DELETED" }
        .sort_by { |p| Client.parse_date(p["Date"]) || Date.new(1900) }
        .each_with_object({}) { |p, h| h[p.dig("Invoice", "InvoiceID")] = p.dig("Account", "Code").presence || p.dig("Account", "Name") }
    end
  end
end

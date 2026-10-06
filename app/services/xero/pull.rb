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

    def tax_rates_csv
      csv(%w[Name TaxType Rate]) do |out|
        @client.get("TaxRates", key: "TaxRates").each do |t|
          next if t["Status"] == "DELETED" || t["Status"] == "ARCHIVED"
          out << [ t["Name"], t["TaxType"], t["EffectiveRate"] ]
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

    # type: "ACCREC" (sales invoices) or "ACCPAY" (bills), issued on or after from.
    def invoices_csv(type, from: nil)
      clauses = [ %(Type=="#{type}") ]
      clauses << %(Date>=DateTime(#{from.year},#{from.month},#{from.day})) if from
      params = { where: clauses.join("&&") }
      csv(INVOICE_HEADERS) do |out|
        @client.each_page("Invoices", params, key: "Invoices").each do |inv|
          next unless LIVE_INVOICE_STATUSES.include?(inv["Status"])
          number = inv["InvoiceNumber"].presence || "XERO-#{inv['InvoiceID'].to_s[0, 8]}"
          paid_from = bank_code_for(inv)
          Array(inv["LineItems"]).each do |li|
            next if li["AccountCode"].blank?
            t1, t2 = Array(li["Tracking"]).first(2)
            out << [ inv.dig("Contact", "Name"), inv.dig("Contact", "EmailAddress"), number, inv["Reference"],
                     date(inv["DateString"] || inv["Date"]), date(inv["DueDateString"] || inv["DueDate"]),
                     li["Description"].presence || "Line", li["Quantity"] || 1, li["UnitAmount"],
                     li["AccountCode"], li["TaxType"], t1&.dig("Name"), t1&.dig("Option"), t2&.dig("Name"), t2&.dig("Option"),
                     inv["AmountPaid"], date(inv["FullyPaidOnDate"]), paid_from ]
          end
        end
      end
    end

    JOURNAL_HEADERS = %w[JournalDate JournalNumber SourceType Reference Description AccountCode AccountName NetAmount TaxAmount TaxType
                         TrackingName1 TrackingOption1 TrackingName2 TrackingOption2].freeze

    def journals_csv(from: nil)
      csv(JOURNAL_HEADERS) do |out|
        @client.each_journal.each do |j|
          jdate = Client.parse_date(j["JournalDate"])
          next if from && jdate && jdate < from
          Array(j["JournalLines"]).each do |line|
            t1, t2 = Array(line["TrackingCategories"]).first(2)
            out << [ jdate&.iso8601, j["JournalNumber"], j["SourceType"], j["Reference"], line["Description"],
                     line["AccountCode"], line["AccountName"], line["NetAmount"], line["TaxAmount"], line["TaxType"],
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

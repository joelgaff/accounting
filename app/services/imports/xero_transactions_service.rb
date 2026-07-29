module Imports
  # Base for Xero's Sales Invoices and Purchases (Bills) CSV exports.
  # Both have identical shape:
  #   *ContactName, EmailAddress, POAddressLine1..4, POCity, PORegion, POPostalCode, POCountry,
  #   *InvoiceNumber, Reference, *InvoiceDate, *DueDate,
  #   Total, InventoryItemCode, *Description, *Quantity, *UnitAmount, Discount, *AccountCode, *TaxType, TaxAmount,
  #   TrackingName1, TrackingOption1, TrackingName2, TrackingOption2, Currency, BrandingTheme
  #
  # Rows are grouped by *InvoiceNumber; each group becomes one Invoice
  # (Sales) or Expense (Bills), each row within the group becomes one
  # LineItem. Idempotent: matches on invoice number and replaces line
  # items in place.
  #
  # Subclasses fill in transaction_class, kind, and how to build the
  # scaffold from group metadata.
  class XeroTransactionsService < BaseService
    REQUIRED = %w[contactname invoicenumber invoicedate duedate description quantity unitamount accountcode].freeze

    def initialize(source, organization:)
      @source       = source
      @organization = organization
    end

    def call
      created = updated = skipped = 0
      errors  = []

      unless settings_ready?
        return Result.new(errors: [settings_error_message])
      end

      rows = self.class.csv(@source)
      missing = REQUIRED - rows.headers.compact
      return Result.new(errors: ["Missing required columns: #{missing.join(", ")}"]) if missing.any?

      rows.group_by { |r| r["invoicenumber"].to_s.strip }.each do |number, group|
        if number.blank?
          skipped += group.size
          errors << "invoice number missing on #{group.size} row(s)"
          next
        end

        begin
          ActiveRecord::Base.transaction do
            resolved_lines = group.map.with_index { |row, i| resolve_line(row, group.first) }
            existed = @organization.public_send(transaction_class.model_name.collection).exists?(xero_invoice_number: number)

            record = upsert_record!(number: number, header_row: group.first, lines: resolved_lines)

            existed ? updated += 1 : created += 1
          end
        rescue Halt => e
          skipped += 1
          errors << "invoice #{number}: #{e.message}"
        rescue ActiveRecord::RecordInvalid => e
          skipped += 1
          errors << "invoice #{number}: #{e.message}"
        end
      end

      Result.new(created: created, updated: updated, skipped: skipped, errors: errors)
    end

    private

    class Halt < StandardError; end

    def transaction_class = raise NotImplementedError
    def contact_kind      = raise NotImplementedError

    # Subclass hook. Given the header row (any row from the group) and the resolved lines,
    # build/find the Invoice or Expense and replace its line items.
    def upsert_record!(number:, header_row:, lines:) = raise NotImplementedError

    def resolve_line(row, header_row)
      account = @organization.plutus_accounts.find_by(code: row["accountcode"].to_s.strip)
      raise Halt, "account code #{row['accountcode'].inspect} not found — import your Chart of Accounts first" unless account

      tax_rate = nil
      if row["taxtype"].present?
        tax_rate = @organization.tax_rates.find_by(xero_tax_type: row["taxtype"].to_s.strip)
        raise Halt, "tax type #{row['taxtype'].inspect} not found — add it under Tax rates first" unless tax_rate
      end

      {
        description: row["description"].to_s.strip,
        quantity:    BigDecimal(row["quantity"].to_s.presence || "1"),
        unit_amount: BigDecimal(row["unitamount"].to_s),
        account:     account,
        tax_rate:    tax_rate
      }
    end

    def resolve_contact(name)
      @organization.contacts.find_or_create_by!(name: name.to_s.strip) do |c|
        c.kind = contact_kind
      end
    end

    def settings_ready?           = true   # subclasses override
    def settings_error_message    = "settings not configured"
  end
end

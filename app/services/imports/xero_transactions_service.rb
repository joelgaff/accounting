module Imports
  # Base for Xero's Sales Invoices and Purchases (Bills) CSV exports; each row
  # group becomes one Document (an Invoice or a Bill).
  # Both have identical shape:
  #   *ContactName, EmailAddress, POAddressLine1..4, POCity, PORegion, POPostalCode, POCountry,
  #   *InvoiceNumber, Reference, *InvoiceDate, *DueDate,
  #   Total, InventoryItemCode, *Description, *Quantity, *UnitAmount, Discount, *AccountCode, *TaxType, TaxAmount,
  #   TrackingName1, TrackingOption1, TrackingName2, TrackingOption2, Currency, BrandingTheme
  #
  # Three optional columns beyond Xero's own export carry settlement across:
  # AmountPaid, FullyPaidOnDate and BankAccount (a code or name from the Chart
  # of Accounts). Xero's CSV doesn't include them, but its API does, so a pull
  # from the API can record the payment in the same pass. A row without
  # BankAccount settles against the bank account in Settings; files without
  # any of the columns import exactly as before.
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

    # Stamped on payments this importer creates, so a re-import corrects its own
    # figure and never touches a payment somebody entered by hand.
    PAYMENT_REFERENCE = "Xero import".freeze

    def initialize(source, organization:)
      @source       = source
      @organization = organization
    end

    def call
      created = updated = skipped = 0
      errors  = []

      unless settings_ready?
        return Result.new(errors: [ settings_error_message ])
      end

      rows = self.class.csv(@source)
      missing = REQUIRED - rows.headers.compact
      return Result.new(errors: [ "Missing required columns: #{missing.join(", ")}" ]) if missing.any?

      rows.group_by { |r| r["invoicenumber"].to_s.strip }.each do |number, group|
        if number.blank?
          skipped += group.size
          errors << "invoice number missing on #{group.size} row(s)"
          next
        end

        begin
          ActiveRecord::Base.transaction(requires_new: true) do
            resolved_lines = group.map.with_index { |row, i| resolve_line(row, group.first) }
            existed = find_existing(number).present?

            record = upsert_record!(number: number, header_row: group.first, lines: resolved_lines)
            warning = sync_payment!(record, group.first)
            errors << "invoice #{number}: #{warning}" if warning

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
    # build/find the document and replace its line items.
    def upsert_record!(number:, header_row:, lines:) = raise NotImplementedError

    # The document already imported under this Xero number, if any.
    def find_existing(number)
      transaction_class.joins(:document)
                       .where(documents: { organization_id: @organization.id })
                       .find_by(xero_invoice_number: number)&.document
    end

    # Replace the document's lines and re-post it; a brand-new document posts
    # itself on create.
    def replace_lines!(document, lines, was_new:)
      document.line_items.destroy_all unless was_new
      document.line_items.reload      unless was_new
      lines.each { |attrs| document.line_items.build(attrs) }
      document.save!
      document.repost_to_ledger! unless was_new
    end

    # Mirrors Xero's settlement onto the record: one payment for the amount Xero
    # reports as paid, dated the day it was fully settled. Returns a warning
    # string when the payment can't be recorded, nil when there's nothing to do.
    def sync_payment!(record, header_row)
      return nil unless header_row.headers.include?("amountpaid")

      record.payments.where(reference: PAYMENT_REFERENCE).each do |payment|
        Ledger.reset_for(payment)
        payment.destroy!
      end

      paid = BigDecimal(header_row["amountpaid"].to_s.presence || "0")
      return nil if paid <= 0

      bank, problem = resolve_bank_account(header_row)
      return problem if problem

      if paid > record.total
        return "Xero reports #{'%.2f' % paid} paid but the imported lines total " \
               "#{'%.2f' % record.total} — payment not recorded"
      end

      paid_on = BaseService.parse_xero_date(header_row["fullypaidondate"]) ||
                BaseService.parse_xero_date(header_row["paidon"]) ||
                BaseService.parse_xero_date(header_row["invoicedate"])

      record.payments.create!(
        organization: @organization,
        amount:       paid,
        paid_on:      paid_on,
        bank_account: bank,
        reference:    PAYMENT_REFERENCE
      )
      nil
    end

    # The row's BankAccount wins; Settings is the fallback. Returns [account, nil]
    # or [nil, warning] — a bad bank never blocks the invoice itself.
    def resolve_bank_account(header_row)
      key = header_row["bankaccount"].to_s.strip
      if key.present?
        bank = @organization.bank_accounts.find_by_code_or_name(key)
        return [ bank, nil ] if bank
        return [ nil, "bank account #{key.inspect} not found among your bank accounts — payment not recorded" ]
      end

      bank = @organization.settings.bank_account
      return [ nil, "paid amount ignored — set a bank account under Settings first" ] if bank.nil?
      [ bank, nil ]
    end

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
        tax_rate:    tax_rate,
        tracking_option_ids: tracking.option_ids_for(row)
      }
    end

    def tracking = @tracking ||= TrackingResolver.new(@organization)

    def resolve_contact(name)
      @organization.contacts.find_or_create_by!(name: name.to_s.strip) do |c|
        c.kind = contact_kind
      end
    end

    def settings_ready?           = true   # subclasses override
    def settings_error_message    = "settings not configured"
  end
end

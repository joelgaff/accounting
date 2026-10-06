module Imports
  # Xero's spend money and receive money (the BankTransactions endpoint),
  # one row per line, grouped by BankTransactionID:
  #   Type (SPEND|RECEIVE), BankTransactionID, Date, ContactName, Reference, BankAccount,
  #   Description, Quantity, UnitAmount, AccountCode, TaxType,
  #   TrackingName1, TrackingOption1, TrackingName2, TrackingOption2
  # UnitAmount is net of tax. SPEND becomes an Expense, RECEIVE a Deposit;
  # idempotent on the Xero id, replacing lines in place on a re-import.
  class XeroBankTransactionsService < BaseService
    REQUIRED = %w[type banktransactionid date bankaccount accountcode unitamount].freeze
    TYPES    = { "SPEND" => Expense, "RECEIVE" => Deposit }.freeze

    def initialize(source, organization:)
      @source       = source
      @organization = organization
    end

    def call
      created = updated = skipped = 0
      errors  = []
      rows    = self.class.csv(@source)
      missing = REQUIRED - rows.headers.compact
      return Result.new(errors: [ "Missing required columns: #{missing.join(", ")}" ]) if missing.any?

      rows.group_by { |r| r["banktransactionid"].to_s.strip }.each do |xid, group|
        first = group.first
        klass = TYPES[first["type"].to_s.strip.upcase]
        if xid.blank? || klass.nil?
          skipped += 1
          errors << "bank transaction #{xid.presence || '(no id)'}: type #{first['type'].inspect} is not spend or receive"
          next
        end

        begin
          ActiveRecord::Base.transaction(requires_new: true) do
            bank = @organization.bank_accounts.find_by_code_or_name(first["bankaccount"].to_s.strip)
            raise Halt, "bank account #{first['bankaccount'].inspect} not found" unless bank
            contact  = first["contactname"].to_s.strip.presence && Contact.find_or_create_named(@organization, first["contactname"].to_s.strip, kind: klass == Expense ? "vendor" : "customer")
            lines    = group.map { |row| resolve_line(row) }
            existing = klass.joins(:document).where(documents: { organization_id: @organization.id }).find_by(xero_id: xid)&.document
            document = existing || @organization.documents.build(documentable: klass.new(xero_id: xid), source: "xero_import")
            was_new  = document.new_record?

            document.assign_attributes(
              contact:   contact,
              date:      BaseService.parse_xero_date(first["date"]),
              reference: first["reference"].to_s.strip.presence,
              memo:      (first["description"].to_s.strip.presence if group.size == 1)
            )
            document.documentable.bank_account = bank
            document.documentable.vendor = contact&.name || first["reference"].to_s.strip.presence || first["description"].to_s.strip.presence || "(Xero)" if klass == Expense

            document.line_items.destroy_all unless was_new
            document.line_items.reload      unless was_new
            lines.each { |attrs| document.line_items.build(attrs) }
            document.save!
            document.repost_to_ledger! unless was_new
            existing ? updated += 1 : created += 1
          end
        rescue Halt, ActiveRecord::RecordInvalid => e
          skipped += 1
          errors << "bank transaction #{xid}: #{e.message}"
        end
      end

      Result.new(created: created, updated: updated, skipped: skipped, errors: errors)
    end

    private

    class Halt < StandardError; end

    def tracking = @tracking ||= TrackingResolver.new(@organization)

    def resolve_line(row)
      account = @organization.plutus_accounts.find_by(code: row["accountcode"].to_s.strip)
      raise Halt, "account code #{row['accountcode'].inspect} not in the Chart of Accounts" unless account
      tax_rate = nil
      if row["taxtype"].present?
        tax_rate = @organization.tax_rates.find_by(xero_tax_type: row["taxtype"].to_s.strip)
        raise Halt, "tax type #{row['taxtype'].inspect} not found among tax rates" unless tax_rate
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
  end
end

module Imports
  # Xero's bank transfers (the BankTransfers endpoint), one per row:
  #   BankTransferID, Date, Amount, FromBankAccount, ToBankAccount (codes or names)
  # Each becomes a Transfer; idempotent on the Xero id.
  class XeroBankTransfersService < BaseService
    REQUIRED = %w[banktransferid date amount frombankaccount tobankaccount].freeze

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

      rows.each do |row|
        xid = row["banktransferid"].to_s.strip
        begin
          raise ActiveRecord::RecordInvalid if xid.blank?
          from = @organization.bank_accounts.find_by_code_or_name(row["frombankaccount"].to_s.strip)
          to   = @organization.bank_accounts.find_by_code_or_name(row["tobankaccount"].to_s.strip)
          raise Missing, "bank account #{row['frombankaccount'].inspect} not found" unless from
          raise Missing, "bank account #{row['tobankaccount'].inspect} not found"   unless to

          existing = Transfer.joins(:document).where(documents: { organization_id: @organization.id }).find_by(xero_id: xid)&.document
          document = existing || @organization.documents.build(documentable: Transfer.new(xero_id: xid), source: "xero_import")
          document.assign_attributes(date: BaseService.parse_xero_date(row["date"]), total: BigDecimal(row["amount"].to_s),
                                     reference: row["reference"].to_s.strip.presence)
          document.transfer.assign_attributes(from_bank_account: from, to_bank_account: to)
          was_new = document.new_record?
          document.save!
          document.repost_to_ledger! unless was_new
          existing ? updated += 1 : created += 1
        rescue Missing, ActiveRecord::RecordInvalid => e
          skipped += 1
          errors << "transfer #{xid.presence || '(no id)'}: #{e.message}"
        end
      end

      Result.new(created: created, updated: updated, skipped: skipped, errors: errors)
    end

    private

    class Missing < StandardError; end
  end
end

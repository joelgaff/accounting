module Imports
  # Parses a bank statement CSV (plain shape or Xero's export) and creates
  # BankTransaction records in the `unmatched` state. Ledger posting waits
  # until the user matches or categorizes each row from the reconciliation
  # queue — no more suspense-account auto-posts.
  class BankStatementService < BaseService
    LegacyResult = Struct.new(:imported, :duplicates, :errors, keyword_init: true)

    REQUIRED = %w[date amount].freeze

    def initialize(source, bank_account:, organization:)
      @source       = source
      @bank_account = bank_account
      @organization = organization
    end

    def call
      imported   = 0
      duplicates = 0
      errors     = []

      rows    = self.class.csv(@source)
      missing = REQUIRED - rows.headers.compact
      return LegacyResult.new(imported: 0, duplicates: 0,
                              errors: ["Missing required columns: #{missing.map(&:capitalize).join(", ")}"]) if missing.any?

      rows.each.with_index(2) do |row, line|
        begin
          date        = BaseService.parse_xero_date(row["date"])
          description = compose_description(row)
          amount      = BigDecimal(row["amount"].to_s.strip)
          reference   = row["reference"].to_s.strip.presence

          txn = @organization.bank_transactions.build(
            bank_account: @bank_account, posted_on: date,
            description: description, amount: amount, reference: reference,
            status: "unmatched"
          )
          if txn.save
            imported += 1
          elsif txn.errors[:base].blank? && txn.errors.details.any? { |_, dets| dets.any? { |d| d[:error] == :taken } }
            duplicates += 1
          elsif @organization.bank_transactions.exists?(bank_account: @bank_account, posted_on: date,
                                                        description: description, amount: amount)
            duplicates += 1
          else
            errors << "row #{line}: #{txn.errors.full_messages.join(', ')}"
          end
        rescue ActiveRecord::RecordNotUnique
          duplicates += 1
        rescue => e
          errors << "row #{line}: #{e.message}"
        end
      end

      LegacyResult.new(imported: imported, duplicates: duplicates, errors: errors)
    end

    private

    def compose_description(row)
      [row["payee"], row["description"]].compact.map { |s| s.to_s.strip }.reject(&:blank?).join(" — ").presence || "(no description)"
    end
  end
end

module Imports
  # Parses a bank statement CSV (plain shape or Xero's export) and creates
  # BankTransaction records in the `unmatched` state, keeping payee apart from
  # the description. Ledger posting waits until each line is reconciled; bank
  # rules run over the new lines as a last step.
  class BankStatementService < BaseService
    LegacyResult = Struct.new(:imported, :duplicates, :errors, :rules_applied, :rules_suggested, keyword_init: true)

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
      created    = []

      rows    = self.class.csv(@source)
      missing = REQUIRED - rows.headers.compact
      return LegacyResult.new(imported: 0, duplicates: 0, rules_applied: 0, rules_suggested: 0,
                              errors: [ "Missing required columns: #{missing.map(&:capitalize).join(", ")}" ]) if missing.any?

      rows.each.with_index(2) do |row, line|
        begin
          date        = BaseService.parse_xero_date(row["date"])
          payee       = row["payee"].to_s.strip
          description = row["description"].to_s.strip.presence || payee.presence || "(no description)"
          amount      = BigDecimal(row["amount"].to_s.strip)
          reference   = row["reference"].to_s.strip.presence

          txn = @organization.bank_transactions.build(
            bank_account: @bank_account, posted_on: date, payee: payee,
            description: description, amount: amount, reference: reference,
            status: "unmatched"
          )
          if txn.save
            imported += 1
            created << txn
          elsif @organization.bank_transactions.exists?(bank_account: @bank_account, posted_on: date, payee: payee,
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

      rules = Reconciliation::ApplyRules.new(@organization, created).call
      LegacyResult.new(imported: imported, duplicates: duplicates, errors: errors,
                       rules_applied: rules.applied, rules_suggested: rules.suggested)
    end
  end
end

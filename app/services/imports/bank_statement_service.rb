module Imports
  # Creates unmatched BankTransaction rows from a statement: a CSV (plain
  # shape or Xero's export) or an array of row hashes from a feed or an OFX
  # file. Lines with the bank's own id dedupe on it and adopt an earlier
  # id-less CSV row for the same line; id-less rows dedupe on their shape.
  # Ledger posting waits until each line is reconciled; bank rules run over
  # the new lines as a last step.
  class BankStatementService < BaseService
    LegacyResult = Struct.new(:imported, :duplicates, :errors, :rules_applied, :rules_suggested, keyword_init: true)

    REQUIRED = %w[date amount].freeze

    def initialize(source, bank_account:, organization:)
      @source       = source
      @bank_account = bank_account
      @organization = organization
    end

    def call
      rows = @source.is_a?(Array) ? @source : csv_rows
      return rows if rows.is_a?(LegacyResult)   # header problem

      imported = duplicates = 0
      errors   = []
      created  = []

      rows.each.with_index(2) do |row, line|
        row = row.to_h.symbolize_keys
        begin
          outcome = import_row(row)
          case outcome
          when BankTransaction then imported += 1; created << outcome
          when :duplicate      then duplicates += 1
          else                      errors << "row #{line}: #{outcome}"
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

    private

    def csv_rows
      table   = self.class.csv(@source)
      missing = REQUIRED - table.headers.compact
      if missing.any?
        return LegacyResult.new(imported: 0, duplicates: 0, rules_applied: 0, rules_suggested: 0,
                                errors: [ "Missing required columns: #{missing.map(&:capitalize).join(", ")}" ])
      end
      table.map do |row|
        payee = row["payee"].to_s.strip
        { posted_on: BaseService.parse_xero_date(row["date"]), amount: BigDecimal(row["amount"].to_s.strip),
          payee: payee, description: row["description"].to_s.strip.presence || payee.presence,
          reference: row["reference"].to_s.strip.presence, external_id: row["externalid"].to_s.strip.presence }
      end
    end

    def import_row(row)
      posted_on   = row[:posted_on] || row[:date]
      payee       = row[:payee].to_s.strip
      description = row[:description].to_s.strip.presence || payee.presence || "(no description)"
      amount      = BigDecimal(row[:amount].to_s)
      external_id = row[:external_id].to_s.strip.presence
      scope       = @organization.bank_transactions.where(bank_account: @bank_account)

      if external_id
        return :duplicate if scope.exists?(external_id: external_id)
        if (orphan = scope.find_by(external_id: nil, posted_on: posted_on, amount: amount, description: description))
          orphan.update!(external_id: external_id, payee: payee.presence || orphan.payee)
          return :duplicate
        end
      elsif scope.exists?(external_id: nil, posted_on: posted_on, amount: amount, payee: payee, description: description)
        return :duplicate
      end

      txn = scope.build(organization: @organization, posted_on: posted_on, payee: payee, description: description,
                        amount: amount, reference: row[:reference].presence, external_id: external_id, status: "unmatched")
      txn.save ? txn : txn.errors.full_messages.join(", ")
    end
  end
end

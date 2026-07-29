class BankImportService < Imports::BaseService
  # Backwards-compat return shape — this service predates the shared Result
  # struct and callers/tests read :imported (not :created). Slice J will
  # replace this whole service with Imports::BankStatementService; keeping
  # the legacy shape until then avoids churn.
  LegacyResult = Struct.new(:imported, :skipped, :errors, keyword_init: true)

  REQUIRED_COLUMNS = %w[date amount].freeze

  def initialize(source, bank_account:, paired_account:)
    @source         = source
    @bank_account   = bank_account
    @paired_account = paired_account
  end

  def call
    imported = 0
    skipped  = 0
    errors   = []

    rows = self.class.csv(@source)
    missing = REQUIRED_COLUMNS - rows.headers.compact
    if missing.any?
      return LegacyResult.new(imported: 0, skipped: 0,
                              errors: ["Missing required columns: #{missing.map(&:capitalize).join(", ")}"])
    end

    rows.each.with_index(2) do |row, line|
      begin
        date        = self.class.parse_xero_date(row["date"])
        description = [row["payee"], row["description"]].compact_blank.map { |s| s.to_s.strip }.reject(&:blank?).join(" — ").presence || "(no description)"
        amount      = BigDecimal(row["amount"].to_s.strip)

        debit_account, credit_account =
          amount.positive? ? [@bank_account, @paired_account]
                           : [@paired_account, @bank_account]

        Ledger.post(
          description: "Import #{date.iso8601}: #{description}",
          date: date,
          commercial_document: nil,
          debits:  [{ account: debit_account,  amount: amount.abs }],
          credits: [{ account: credit_account, amount: amount.abs }]
        )
        imported += 1
      rescue => e
        skipped += 1
        errors << "row #{line}: #{e.message}"
      end
    end

    LegacyResult.new(imported: imported, skipped: skipped, errors: errors)
  end
end

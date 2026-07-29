require "csv"

class BankImportService
  Result = Struct.new(:imported, :skipped, :errors, keyword_init: true)

  REQUIRED_COLUMNS = %w[Date Description Amount].freeze

  def initialize(source, bank_account:, paired_account:)
    @source         = source
    @bank_account   = bank_account
    @paired_account = paired_account
  end

  def call
    imported = 0
    skipped  = 0
    errors   = []

    data = @source.respond_to?(:read) ? @source.read : @source
    csv  = CSV.parse(data, headers: true)

    missing = REQUIRED_COLUMNS - csv.headers.compact
    if missing.any?
      return Result.new(imported: 0, skipped: 0, errors: ["Missing required columns: #{missing.join(", ")}"])
    end

    csv.each.with_index(2) do |row, line|
      begin
        date        = Date.parse(row["Date"].to_s)
        description = row["Description"].to_s.strip
        amount      = BigDecimal(row["Amount"].to_s.strip)

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

    Result.new(imported: imported, skipped: skipped, errors: errors)
  end
end

module Reports
  class BalanceSheet < BaseReport
    Row = Struct.new(:account, :amount, keyword_init: true)

    # Balance Sheet is as-of a date, not a range. Ignores `from`.
    def initialize(organization:, as_of: Date.current, **_)
      super(organization: organization, from: nil, to: as_of)
      @as_of = as_of
    end
    attr_reader :as_of

    def asset_rows     = rows_for("Plutus::Asset")
    def liability_rows = rows_for("Plutus::Liability")
    def equity_rows    = rows_for("Plutus::Equity")

    def total_assets      = asset_rows.sum(&:amount)
    def total_liabilities = liability_rows.sum(&:amount)
    def total_equity      = equity_rows.sum(&:amount)

    YearRow = Struct.new(:year, :amount, keyword_init: true)

    # Earnings the ledger has accumulated but never closed to an equity
    # account. Xero shows the same split: prior years as retained earnings,
    # the year in progress as current year earnings. The fiscal year is the
    # calendar year. Nothing is posted; this is presentation only.
    def earnings_by_year
      @earnings_by_year ||= begin
        rel = Plutus::Amount.joins(:entry, :account)
                            .where(plutus_accounts: { tenant_id: organization.id, type: %w[Plutus::Revenue Plutus::Expense] })
                            .where(plutus_entries: { date: ..as_of })
        year = Arel.sql("strftime('%Y', plutus_entries.date)")
        signed = Arel.sql(<<~SQL.squish)
          SUM(CASE
                WHEN plutus_accounts.type = 'Plutus::Revenue' AND plutus_amounts.type = 'Plutus::CreditAmount' THEN plutus_amounts.amount
                WHEN plutus_accounts.type = 'Plutus::Revenue' THEN -plutus_amounts.amount
                WHEN plutus_amounts.type = 'Plutus::DebitAmount' THEN -plutus_amounts.amount
                ELSE plutus_amounts.amount
              END * CASE WHEN plutus_accounts.contra THEN -1 ELSE 1 END)
        SQL
        rel.group(year).order(year).pluck(year, signed)
           .map { |y, amt| YearRow.new(year: y.to_i, amount: BigDecimal(amt.to_s).round(2)) }
      end
    end

    def prior_year_rows        = earnings_by_year.select { |r| r.year < as_of.year }.reject { |r| r.amount.zero? }
    def retained_earnings      = prior_year_rows.sum(&:amount)
    def current_year_earnings  = earnings_by_year.find { |r| r.year == as_of.year }&.amount || BigDecimal("0")
    def current_year_start     = as_of.beginning_of_year

    # Everything the ledger has earned and not closed: prior years plus the
    # year in progress.
    def net_income = retained_earnings + current_year_earnings

    def total_liabilities_and_equity
      total_liabilities + total_equity + net_income
    end

    def balanced?
      (total_assets - total_liabilities_and_equity).abs < BigDecimal("0.01")
    end

    private

    def rows_for(type)
      accounts_scope.where(type: type).order(:code, :name).map do |a|
        Row.new(account: a, amount: account_balance(a))
      end.reject { |r| r.amount.zero? }
    end
  end
end

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

    # Net income (retained earnings for the period) closes the books.
    def net_income
      pnl = ProfitAndLoss.new(organization: organization, to: as_of)
      pnl.net_income
    end

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

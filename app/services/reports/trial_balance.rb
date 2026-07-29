module Reports
  class TrialBalance < BaseReport
    Row = Struct.new(:account, :debit, :credit, keyword_init: true)

    def rows
      @rows ||= accounts_scope.order(:type, :code, :name).map do |a|
        d = amounts_for(a, Plutus::DebitAmount)
        c = amounts_for(a, Plutus::CreditAmount)
        # For debit-normal accounts (Asset, Expense), positive delta shows as debit.
        # For credit-normal (Liability, Equity, Revenue), positive delta shows as credit.
        delta = d - c
        case a
        when Plutus::Asset, Plutus::Expense
          delta.positive? ? Row.new(account: a, debit: delta,      credit: BigDecimal("0"))
                          : Row.new(account: a, debit: BigDecimal("0"), credit: -delta)
        else
          delta.negative? ? Row.new(account: a, debit: BigDecimal("0"), credit: -delta)
                          : Row.new(account: a, debit: delta,      credit: BigDecimal("0"))
        end
      end.reject { |r| r.debit.zero? && r.credit.zero? }
    end

    def total_debit  = rows.sum(&:debit)
    def total_credit = rows.sum(&:credit)
    def balanced?    = (total_debit - total_credit).abs < BigDecimal("0.01")
  end
end

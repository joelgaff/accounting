module Reports
  class ProfitAndLoss < BaseReport
    Row = Struct.new(:account, :amount, keyword_init: true)

    def revenue_rows
      @revenue_rows ||= accounts_scope.where(type: "Plutus::Revenue").order(:code, :name).map do |a|
        Row.new(account: a, amount: account_balance(a))
      end
    end

    def expense_rows
      @expense_rows ||= accounts_scope.where(type: "Plutus::Expense").order(:code, :name).map do |a|
        Row.new(account: a, amount: account_balance(a))
      end
    end

    def total_revenue = revenue_rows.sum(&:amount)
    def total_expenses = expense_rows.sum(&:amount)
    def net_income    = total_revenue - total_expenses
  end
end

module Reconciliation
  # Per bank account: what the ledger says, what the last statement said, and
  # how much is still waiting in the queue.
  class Summary
    Row = Struct.new(:bank_account, :ledger_balance, :statement_balance, :statement_balance_at, :unmatched_count, :unmatched_total, keyword_init: true) do
      def difference = statement_balance && (statement_balance - ledger_balance)
    end

    def initialize(organization) = @org = organization

    def rows
      counts = @org.bank_transactions.unmatched.group(:bank_account_id).count
      totals = @org.bank_transactions.unmatched.group(:bank_account_id).sum(:amount)
      @org.bank_accounts.active.ordered.includes(:account).map do |bank|
        balance = bank.balance
        balance = -balance if bank.credit_card?   # a card's ledger balance is what we owe; the statement shows the same sign
        Row.new(bank_account: bank, ledger_balance: balance,
                statement_balance: bank.statement_balance, statement_balance_at: bank.statement_balance_at,
                unmatched_count: counts[bank.id] || 0, unmatched_total: totals[bank.id] || BigDecimal("0"))
      end
    end
  end
end

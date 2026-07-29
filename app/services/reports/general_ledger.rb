module Reports
  class GeneralLedger < BaseReport
    Line = Struct.new(:date, :entry, :description, :debit, :credit, :running_balance, keyword_init: true)

    def initialize(organization:, account:, from: nil, to: nil)
      super(organization: organization, from: from, to: to)
      @account = account
    end
    attr_reader :account

    def lines
      @lines ||= begin
        debits  = Plutus::DebitAmount.where(account_id: account.id).includes(:entry)
        credits = Plutus::CreditAmount.where(account_id: account.id).includes(:entry)

        rows = (debits.map { |a| [:debit, a] } + credits.map { |a| [:credit, a] })
                 .filter { |_, a| in_window?(a.entry) }
                 .sort_by { |_, a| [a.entry.date || a.entry.created_at.to_date, a.entry.id] }

        running = opening_balance
        rows.map do |side, amount|
          d = side == :debit  ? amount.amount : BigDecimal("0")
          c = side == :credit ? amount.amount : BigDecimal("0")
          running += debit_normal? ? (d - c) : (c - d)
          Line.new(
            date: amount.entry.date || amount.entry.created_at.to_date,
            entry: amount.entry,
            description: amount.entry.description,
            debit: d, credit: c, running_balance: running
          )
        end
      end
    end

    def opening_balance
      return BigDecimal("0") unless from
      d = Plutus::DebitAmount.joins(:entry).where(account_id: account.id, plutus_entries: { date: ...from }).sum(:amount)
      c = Plutus::CreditAmount.joins(:entry).where(account_id: account.id, plutus_entries: { date: ...from }).sum(:amount)
      debit_normal? ? (d - c) : (c - d)
    end

    def closing_balance = lines.last&.running_balance || opening_balance

    private

    def in_window?(entry)
      d = entry.date || entry.created_at.to_date
      return false if from && d < from
      return false if to   && d > to
      true
    end

    def debit_normal?
      account.is_a?(Plutus::Asset) || account.is_a?(Plutus::Expense)
    end
  end
end

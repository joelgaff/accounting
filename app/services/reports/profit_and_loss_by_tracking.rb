module Reports
  # Profit & Loss with one column per option of a tracking category, plus
  # "Unassigned". Built from document lines and journal lines rather than
  # the ledger, because tracking lives on lines; the ledger's own P&L is the
  # check figure (the report shows both totals).
  class ProfitAndLossByTracking < BaseReport
    Row = Struct.new(:account, :by_option, :total, keyword_init: true)
    UNASSIGNED = :unassigned

    def initialize(organization:, category:, from: nil, to: nil)
      super(organization: organization, from: from, to: to)
      @category = category
    end
    attr_reader :category

    def columns = category.options.to_a + [ UNASSIGNED ]

    def revenue_rows = rows_for("Plutus::Revenue")
    def expense_rows = rows_for("Plutus::Expense")

    def column_total(rows, column) = rows.sum { |r| r.by_option[column] || BigDecimal("0") }
    def net_income(column)         = column_total(revenue_rows, column) - column_total(expense_rows, column)
    def total_revenue              = revenue_rows.sum(&:total)
    def total_expenses             = expense_rows.sum(&:total)
    def ledger_net_income          = ProfitAndLoss.new(organization: organization, from: from, to: to).net_income

    private

    def rows_for(type)
      accounts = accounts_scope.where(type: type).order(:code, :name).to_a
      accounts.filter_map do |account|
        cells = cells_by_option[account.id] or next
        Row.new(account: account, by_option: cells, total: cells.values.sum)
      end
    end

    # { account_id => { option | :unassigned => amount } } over live documents in the window.
    def cells_by_option
      @cells ||= begin
        cells = Hash.new { |h, k| h[k] = Hash.new(BigDecimal("0")) }
        document_lines.each { |account_id, option, amount| cells[account_id][option] += amount }
        journal_lines.each  { |account_id, option, amount| cells[account_id][option] += amount }
        cells
      end
    end

    def documents_in_window
      scope = organization.documents.live.where(documentable_type: %w[Invoice Bill Expense Deposit])
      scope = scope.where(date: from..) if from
      scope = scope.where(date: ..to)   if to
      scope
    end

    # Non-recoverable tax folds onto purchase lines the way Expense#ledger_legs
    # posts it.
    def document_lines
      LineItem.where(lineable_type: "Document", lineable_id: documents_in_window.select(:id))
              .includes(:account, :tax_rate, :lineable, tracking_selections: :tracking_option)
              .filter_map do |li|
        account = li.account
        next unless account.is_a?(Plutus::Revenue) || account.is_a?(Plutus::Expense)
        purchase = li.lineable.documentable_type.in?(%w[Bill Expense])
        amount   = li.amount
        amount  += li.tax_total if purchase && li.tax_rate && li.tax_rate.asset_account.nil?
        # A sales line credits its account, a purchase line debits it; a
        # refund deposited to an expense account therefore reduces the expense.
        amount = -amount if purchase == account.is_a?(Plutus::Revenue)
        [ account.id, option_of(li), amount ]
      end
    end

    def journal_lines
      docs = organization.documents.live.journal_entries
      docs = docs.where(date: from..) if from
      docs = docs.where(date: ..to)   if to
      JournalLine.where(journal_entry_id: docs.select(:documentable_id))
                 .includes(:account, tracking_selections: :tracking_option)
                 .filter_map do |line|
        account = line.account
        amount  = case account
        when Plutus::Revenue then line.credit_amount - line.debit_amount
        when Plutus::Expense then line.debit_amount - line.credit_amount
        end
        next unless amount
        [ account.id, option_of(line), amount ]
      end
    end

    def option_of(line)
      line.tracking_selections.find { |s| s.tracking_category_id == category.id }&.tracking_option || UNASSIGNED
    end
  end
end

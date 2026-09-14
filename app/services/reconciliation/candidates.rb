module Reconciliation
  # What each statement line on the page could be matched to, loaded once for
  # the whole page rather than once per row.
  class Candidates
    Set = Struct.new(:documents, :transfers, keyword_init: true) do
      def any? = documents.any? || transfers.any?
    end
    TOLERANCE = BigDecimal("0.05")

    def initialize(organization, transactions)
      @org  = organization
      @txns = Array(transactions)
      @memo = {}
    end

    def for(txn)
      @memo[txn.id] ||= build(txn)
    end

    private

    def receivables
      @receivables ||= @org.documents.invoices.includes(:contact, :payments, :documentable).select(&:outstanding?)
    end

    def payables
      @payables ||= @org.documents.bills.includes(:contact, :payments, :documentable).select(&:outstanding?)
    end

    # Expenses and deposits nobody has reconciled yet.
    def direct
      @direct ||= @org.documents.where(documentable_type: %w[Expense Deposit])
                      .where.missing(:bank_transactions)
                      .includes(:contact, :documentable).to_a
    end

    def transfers
      @transfers ||= @org.documents.transfers
                         .includes(:bank_transactions, documentable: %i[from_bank_account to_bank_account]).to_a
    end

    def build(txn)
      amount    = txn.amount.abs
      low, high = amount * (1 - TOLERANCE), amount * (1 + TOLERANCE)

      docs  = (txn.deposit? ? receivables : payables).select { |d| d.balance_due.between?(low, high) }
      docs += direct.select do |d|
        d.documentable.bank_account_id == txn.bank_account_id && d.total == amount &&
          (txn.deposit? ? d.deposit? : d.expense?)
      end
      tf = transfers.select do |d|
        d.transfer.awaiting_side?(txn.bank_account) && d.transfer.expected_amount_for(txn.bank_account) == txn.amount
      end
      Set.new(documents: docs, transfers: tf)
    end
  end
end

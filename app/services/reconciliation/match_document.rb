module Reconciliation
  # Settle an invoice or bill with this line (a Payment), or link the line to
  # an expense, deposit or transfer that already exists for it.
  class MatchDocument
    class Mismatch < StandardError; end

    def initialize(txn, document)
      @txn      = txn
      @document = document
    end

    def call
      raise Mismatch, "this line is already #{@txn.status}" unless @txn.unmatched?

      Document.transaction do
        if @document.settleable?
          payment = @document.payments.create!(
            organization: @txn.organization,
            amount:       [ @txn.amount.abs, @document.balance_due ].min,
            paid_on:      @txn.posted_on,
            bank_account: @txn.bank_account,
            reference:    @txn.reference
          )
          @txn.match_to!(payment)
        else
          check_direct!
          @txn.match_to!(@document)
        end
      end
      Result.new(transaction: @txn)
    end

    private

    def check_direct!
      type = @document.documentable
      case type
      when Expense
        raise Mismatch, "an expense only matches money out of #{type.bank_account.name}" unless @txn.withdrawal? && type.bank_account_id == @txn.bank_account_id
      when Deposit
        raise Mismatch, "a deposit only matches money into #{type.bank_account.name}" unless @txn.deposit? && type.bank_account_id == @txn.bank_account_id
      when Transfer
        raise Mismatch, "this transfer has no open side for #{@txn.bank_account.name}" unless type.awaiting_side?(@txn.bank_account)
      else
        raise Mismatch, "#{@document.label} cannot be matched to a bank line"
      end
      raise Mismatch, "amounts differ (#{@document.label} is for #{'%.2f' % @document.total})" unless @document.total == @txn.amount.abs
    end
  end
end

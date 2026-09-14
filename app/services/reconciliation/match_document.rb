module Reconciliation
  # Settle an invoice or bill with (part of) this line, or link the line to an
  # expense, deposit or transfer that already exists for it.
  class MatchDocument
    class Mismatch < StandardError; end

    def initialize(txn, document, amount: nil)
      @txn      = txn
      @document = document
      @amount   = amount.present? ? BigDecimal(amount.to_s) : nil
    end

    def call
      raise Mismatch, "this line is already #{@txn.status}" unless @txn.unmatched?

      Document.transaction do
        if @document.settleable?
          amount = @amount || [ @txn.remaining, @document.balance_due ].min
          raise Mismatch, "nothing left to allocate on this line" unless amount.positive?
          raise Mismatch, "#{'%.2f' % amount} is more than the #{'%.2f' % @txn.remaining} left on this line" if amount > @txn.remaining
          @document.payments.create!(
            organization:     @txn.organization,
            amount:           amount,
            paid_on:          @txn.posted_on,
            bank_account:     @txn.bank_account,
            reference:        @txn.reference,
            bank_transaction: @txn
          )
        else
          check_direct!
          @txn.update!(document: @document)
          @document.record_event!(:matched, **bank_line_details)
        end
        @txn.refresh_status!
      end
      Result.new(transaction: @txn)
    end

    private

    def bank_line_details
      { bank_account: @txn.bank_account.name, posted_on: @txn.posted_on.iso8601, amount: @txn.amount.abs,
        description: [ @txn.payee, @txn.description ].compact_blank.join(" ").truncate(80) }
    end

    def check_direct!
      raise Mismatch, "this line already carries #{@txn.document.label}" if @txn.document
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
      raise Mismatch, "amounts differ (#{@document.label} is for #{'%.2f' % @document.total})" unless @document.total == @txn.remaining
    end
  end
end

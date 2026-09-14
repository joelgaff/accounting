module Reconciliation
  # A statement line becomes a transfer to or from another of our accounts.
  # If the other account's statement already holds the mirror line, it is
  # linked to the same transfer in the same step.
  class CreateTransfer
    WINDOW_DAYS = 3   # interbank and ACH lag

    def initialize(txn, other_bank_account:, source: "reconcile")
      @txn    = txn
      @other  = other_bank_account
      @source = source
    end

    def call
      raise MatchDocument::Mismatch, "this line is already #{@txn.status}" unless @txn.unmatched?
      raise MatchDocument::Mismatch, "pick a different account for the other side" if @other.id == @txn.bank_account_id

      from, to = @txn.withdrawal? ? [ @txn.bank_account, @other ] : [ @other, @txn.bank_account ]
      Document.transaction do
        document = @txn.organization.documents.create!(
          date:         @txn.posted_on,
          total:        @txn.amount.abs,
          reference:    @txn.reference,
          memo:         @txn.description,
          source:       @source,
          documentable: Transfer.new(from_bank_account: from, to_bank_account: to)
        )
        @txn.match_to!(document)
        sibling = counterpart
        sibling&.match_to!(document)
        Result.new(transaction: @txn, sibling: sibling)
      end
    end

    private

    # The mirror line: same amount, opposite sign, other account, nearest date
    # within the window.
    def counterpart
      @txn.organization.bank_transactions.unmatched
          .where(bank_account: @other, amount: -@txn.amount)
          .where(posted_on: (@txn.posted_on - WINDOW_DAYS)..(@txn.posted_on + WINDOW_DAYS))
          .to_a.min_by { |o| [ (o.posted_on - @txn.posted_on).abs, o.id ] }
    end
  end
end

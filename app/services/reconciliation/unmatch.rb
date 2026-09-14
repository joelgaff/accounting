module Reconciliation
  # Put a line back in the queue: payments it settled are unwound, a document
  # the reconcile page created for it is removed, one a person made is only
  # unlinked, and a transfer's other side is released too.
  class Unmatch
    def initialize(txn) = @txn = txn

    def call
      @txn.reload
      Document.transaction do
        @txn.payments.to_a.each(&:unwind!)
        if (document = @txn.document)
          if document.transfer?
            document.bank_transactions.where.not(id: @txn.id).each { |other| other.update!(document: nil); other.refresh_status! }
          end
          @txn.update!(document: nil)
          if document.source == "reconcile"
            Ledger.reset_for(document)
            document.destroy!
          end
        end
        @txn.update!(status: "unmatched", bank_rule: nil)
      end
      Result.new(transaction: @txn)
    end
  end
end

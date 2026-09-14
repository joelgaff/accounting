module Reconciliation
  # Split one statement line across several invoices or bills, optionally
  # sweeping whatever is left into a fresh expense or deposit.
  class Allocate
    # allocations: [{ document_id:, amount: }], remainder: { account_id:, tax_rate_id:, contact_name: } or nil
    def initialize(txn, allocations:, remainder: nil)
      @txn         = txn
      @allocations = Array(allocations).map { |a| a.to_h.symbolize_keys }.reject { |a| a[:document_id].blank? || a[:amount].blank? }
      @remainder   = remainder&.to_h&.symbolize_keys
    end

    def call
      raise MatchDocument::Mismatch, "this line is already #{@txn.status}" unless @txn.unmatched?
      raise MatchDocument::Mismatch, "nothing to allocate" if @allocations.empty? && @remainder.blank?
      total = @allocations.sum { |a| BigDecimal(a[:amount].to_s) }
      raise MatchDocument::Mismatch, "allocations total #{'%.2f' % total}, more than the #{'%.2f' % @txn.remaining} left" if total > @txn.remaining

      Document.transaction do
        @allocations.each do |a|
          document = @txn.organization.documents.live.where(documentable_type: %w[Invoice Bill]).find(a[:document_id])
          MatchDocument.new(@txn, document, amount: a[:amount]).call
          @txn.reload
        end
        if @remainder.present? && @remainder[:account_id].present? && @txn.remaining.positive? && @txn.document.nil?
          org = @txn.organization
          Categorize.new(@txn,
            account:      org.plutus_accounts.find(@remainder[:account_id]),
            tax_rate:     @remainder[:tax_rate_id].present? ? org.tax_rates.find(@remainder[:tax_rate_id]) : nil,
            contact_name: @remainder[:contact_name]).call
        end
        @txn.reload.refresh_status!
      end
      Result.new(transaction: @txn)
    end
  end
end

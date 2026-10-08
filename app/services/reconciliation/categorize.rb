module Reconciliation
  # Turn a statement line into a fresh expense (money out) or deposit (money
  # in) with one line item, then link the two.
  class Categorize
    # via: what chose the coding when a person did not type it ("memory").
    def initialize(txn, account:, tax_rate: nil, contact_name: nil, memo: nil, tracking_option_ids: [], source: "reconcile", via: nil)
      @txn          = txn
      @via          = via
      @account      = account
      @tax_rate     = tax_rate
      @tracking     = Array(tracking_option_ids).compact_blank
      @contact_name = contact_name.to_s.strip.presence
      @memo         = memo.to_s.strip.presence
      @source       = source
    end

    def call
      raise MatchDocument::Mismatch, "this line is already #{@txn.status}" unless @txn.unmatched?
      raise MatchDocument::Mismatch, "this line already carries #{@txn.document.label}" if @txn.document
      org      = @txn.organization
      gross    = @txn.remaining
      raise MatchDocument::Mismatch, "nothing left on this line to categorize" unless gross.positive?
      raise MatchDocument::Mismatch, "name who this was with" if @contact_name.nil?
      net, _   = TaxInclusive.split(gross, @tax_rate&.rate)

      Document.transaction do
        document = org.documents.create!(
          date:         @txn.posted_on,
          reference:    @txn.reference,
          memo:         @memo || @txn.description,
          contact_name: @contact_name,                 # the document finds or makes the contact
          source:       @source,
          created_via:  @via,
          documentable: build_type,
          line_items_attributes: [ { description: (@memo || @txn.description.to_s).truncate(120), quantity: 1,
                                     unit_amount: net, account: @account, tax_rate: @tax_rate,
                                     tracking_option_ids: @tracking } ]
        )
        @txn.update!(document: document)
        @txn.refresh_status!
        Result.new(transaction: @txn)
      end
    end

    private

    def build_type
      (@txn.deposit? ? Deposit : Expense).new(bank_account: @txn.bank_account)   # the vendor mirrors the contact
    end
  end
end

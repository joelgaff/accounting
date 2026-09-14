module Reconciliation
  # Turn a statement line into a fresh expense (money out) or deposit (money
  # in) with one line item, then link the two.
  class Categorize
    def initialize(txn, account:, tax_rate: nil, contact_name: nil, memo: nil, source: "reconcile")
      @txn          = txn
      @account      = account
      @tax_rate     = tax_rate
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
      net, _   = TaxInclusive.split(gross, @tax_rate&.rate)
      contact  = @contact_name && Contact.find_or_create_named(org, @contact_name, kind: @txn.deposit? ? "customer" : "vendor")

      Document.transaction do
        document = org.documents.create!(
          date:         @txn.posted_on,
          reference:    @txn.reference,
          memo:         @memo || @txn.description,
          contact:      contact,
          source:       @source,
          documentable: build_type(contact),
          line_items_attributes: [ { description: @txn.description.to_s.truncate(120), quantity: 1,
                                     unit_amount: net, account: @account, tax_rate: @tax_rate } ]
        )
        @txn.update!(document: document)
        @txn.refresh_status!
        Result.new(transaction: @txn)
      end
    end

    private

    def build_type(contact)
      if @txn.deposit?
        Deposit.new(bank_account: @txn.bank_account)
      else
        Expense.new(bank_account: @txn.bank_account, vendor: contact&.name || @txn.description.presence || "(bank import)")
      end
    end
  end
end

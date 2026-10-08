module Reconciliation
  # What the books remember about a payee: how lines with the same key were
  # coded before, from reconciled statement lines and from expenses and
  # deposits entered by hand whose counterparty is named in the line.
  #
  # Loaded once for a page of lines. for(txn) answers a Hit or nil: the most
  # recent coding, how many there were, and whether the last three agree on
  # account and tracking, which is what makes it confident enough for OK.
  class Memory
    CONFIDENT_AFTER = 3

    Hit    = Struct.new(:contact_name, :account, :tax_rate, :tracking_option_ids, :memo, :count, :confident, keyword_init: true) do
      def confident? = confident
      # The keyword arguments Categorize takes.
      def coding = { account: account, tax_rate: tax_rate, contact_name: contact_name, tracking_option_ids: tracking_option_ids, memo: memo }
    end
    Coding = Struct.new(:document, :contact_name, :account, :tax_rate, :tracking_option_ids, :memo, keyword_init: true)

    def initialize(organization, transactions)
      @org  = organization
      @txns = Array(transactions)
      @keys = @txns.filter_map { |t| PayeeKey.for_line(t) }.uniq
      @memo = {}
    end

    def for(txn)
      return @memo[txn.id] if @memo.key?(txn.id)
      @memo[txn.id] = hit_for(txn)
    end

    private

    def hit_for(txn)
      key = PayeeKey.for_line(txn) or return nil
      codings = codings_by_key.fetch(key, []).select { |c| c.document.deposit? == txn.deposit? }
      return nil if codings.empty?

      recent = codings.first(CONFIDENT_AFTER)
      agree  = recent.size >= CONFIDENT_AFTER &&
               recent.map { |c| [ c.account.id, c.tracking_option_ids ] }.uniq.size == 1
      tax    = agree && recent.map { |c| c.tax_rate&.id }.uniq.size == 1 ? recent.first.tax_rate : nil
      newest = codings.first
      Hit.new(contact_name: newest.contact_name, account: newest.account, tax_rate: agree ? tax : newest.tax_rate,
              tracking_option_ids: newest.tracking_option_ids, memo: newest.memo, count: codings.size, confident: agree)
    end

    # key => codings, newest first, each document once.
    def codings_by_key
      @codings_by_key ||= begin
        by_key = Hash.new { |h, k| h[k] = [] }
        seen   = Set.new
        (reconciled_documents + named_documents).each do |key, document, bank_words|
          next unless seen.add?([ key, document.id ])
          line = document.line_items.first or next
          by_key[key] << Coding.new(document: document, contact_name: document.counterparty, account: line.account,
                                    tax_rate: line.tax_rate, tracking_option_ids: line.tracking_option_ids.sort,
                                    memo: why_of(line, bank_words))
        end
        by_key.transform_values { |codings| codings.sort_by { |c| [ c.document.date, c.document.id ] }.reverse }
      end
    end

    # A why someone typed; the bank's own words copied onto the line are not one.
    def why_of(line, bank_words) = Document.why_from(line.description, bank_words)

    def document_scope
      @org.documents.posted.where(documentable_type: %w[Expense Deposit])
          .includes(:contact, :documentable, line_items: [ :account, :tax_rate, :tracking_selections ])
    end

    # Lines already reconciled into an expense or deposit, keyed like the new line.
    def reconciled_documents
      return [] if @keys.empty?
      lines = @org.bank_transactions.where.not(document_id: nil).select(:id, :payee, :description, :document_id).to_a
      wanted = lines.filter_map { |l| key = PayeeKey.for_line(l); [ key, l.document_id, l.description ] if @keys.include?(key) }
      docs   = document_scope.where(id: wanted.map(&:second)).index_by(&:id)
      wanted.filter_map { |key, id, bank_words| [ key, docs[id], bank_words ] if docs[id] }
    end

    # Expenses and deposits entered by hand or imported, whose counterparty's
    # words all appear in the line: "Gusto" is in "gusto payroll".
    def named_documents
      return [] if @keys.empty?
      key_tokens = @keys.to_h { |k| [ k, k.split ] }
      names      = @org.contacts.pluck(:name) + Expense.joins(:document).where(documents: { organization_id: @org.id }).distinct.pluck(:vendor)
      matches    = names.compact.uniq.each_with_object({}) do |name, h|
        tokens = PayeeKey.for(name)&.split or next
        key_tokens.each { |key, kt| (h[name] ||= []) << key if (tokens - kt).empty? }
      end
      return [] if matches.empty?

      contact_ids = @org.contacts.where(name: matches.keys).pluck(:id)
      docs = document_scope.where(contact_id: contact_ids)
                           .or(document_scope.where(documentable_type: "Expense", documentable_id: Expense.where(vendor: matches.keys).select(:id)))
                           .order(date: :desc, id: :desc).limit(200)
      docs.flat_map do |document|
        keys = matches[document.counterparty] || []
        keys.map { |key| [ key, document ] }
      end
    end
  end
end

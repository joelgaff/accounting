module Reconciliation
  # Ranks what a line most likely is: a rule first, then an exact amount
  # over a near amount, closeness in date, words the line shares with the
  # document, and last what the books remember about the payee. Confident
  # suggestions earn a one-click OK; the rest just sort the Match select.
  class Suggester
    Suggestion = Struct.new(:kind, :target, :score, :label, :data, :coding, keyword_init: true) do
      def confident? = score >= 100
    end
    MEMORY_CONFIDENT = 100
    MEMORY_HINT      = 30
    DATE_WINDOW = 7
    STOPWORDS   = %w[the and inc llc ltd payment pmt pos card visa debit credit online ach transfer tfr].freeze

    def initialize(organization, transactions, candidates:, memory: nil)
      @org        = organization
      @txns       = Array(transactions)
      @candidates = candidates
      @memory     = memory
      @rules      = @org.bank_rules.active.ordered.includes(:account, :contact, :transfer_bank_account, :conditions).to_a
      @memo       = {}
      @options = @org.tracking_categories.includes(:options).flat_map(&:options).index_by(&:id)
    end

    def for(txn)
      @memo[txn.id] ||= rank(txn)
    end

    def top(txn) = self.for(txn).first

    private

    def rank(txn)
      set  = @candidates.for(txn)
      out  = set.documents.map { |d| document_suggestion(txn, d) }
      out += set.transfers.map { |d| Suggestion.new(kind: :transfer_side, target: d, score: 100 + date_score(txn.posted_on, d.date, window: 3), label: "#{d.label} · #{d.party_name} · #{'%.2f' % d.total}") }
      out += @candidates.mirror_lines_for(txn).map { |o| Suggestion.new(kind: :transfer_pair, target: o, score: 90 + date_score(txn.posted_on, o.posted_on, window: 3), label: "Transfer #{txn.deposit? ? 'from' : 'to'} #{o.bank_account.name} (#{o.posted_on.iso8601})") }
      out  = out.sort_by { |s| -s.score }
      if (hit = @memory&.for(txn))
        memory = memory_suggestion(txn, hit)
        out.insert(out.index { |s| s.score <= memory.score } || out.size, memory)   # after anything that scores higher
      end
      rule = txn.bank_rule || @rules.detect { |r| r.matches?(txn) }
      out.unshift(Suggestion.new(kind: :rule, target: rule, score: 100, label: "Rule “#{rule.name}”: #{rule.summary}",
                                 coding: Coding.of(account: rule.account, tracking_option_ids: rule.try(:tracking_option_ids), options: @options))) if rule
      out
    end

    def document_suggestion(txn, doc)
      amount = txn.remaining
      due    = doc.settleable? ? doc.balance_due : doc.total
      score  = if due == amount then 100
      elsif doc.settleable? && doc.total == amount then 60      # partly paid, line is the full total
      else 40
      end
      score += date_score(txn.posted_on, doc.date)
      score += 10 * (tokens(txn.payee, txn.description, txn.reference) & tokens(doc.counterparty, doc.reference)).size.clamp(0, 3)
      Suggestion.new(kind: :document, target: doc, score: score, label: "#{doc.title} · #{'%.2f' % due}", coding: Coding.of_document(doc))
    end

    def memory_suggestion(txn, hit)
      account = [ hit.account.code, hit.account.name ].compact_blank.join(" ")
      Suggestion.new(kind: :memory, target: nil, data: hit, score: hit.confident? ? MEMORY_CONFIDENT : MEMORY_HINT,
                     label: "#{txn.deposit? ? 'Deposit' : 'Expense'} · #{hit.contact_name.presence || 'no contact'}",
                     coding: Coding.of(account: hit.account, tracking_option_ids: hit.tracking_option_ids, options: @options))
    end

    def date_score(a, b, window: DATE_WINDOW)
      days = (a - b).abs.to_i
      days > window ? 0 : ((window - days) * 3)
    end

    def tokens(*strings)
      strings.compact.join(" ").downcase.scan(/[a-z0-9]{3,}/) - STOPWORDS
    end
  end
end

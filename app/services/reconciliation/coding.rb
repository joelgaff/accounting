module Reconciliation
  # The account and tracking behind a document or a suggested coding, as the
  # names a reader recognises, for the chips on a reconcile card.
  Coding = Struct.new(:accounts, :tracking, keyword_init: true) do
    def any? = accounts.any? || tracking.any?

    def self.of_document(document)
      lines = document.line_items.to_a
      new(accounts: lines.map { |l| display(l.account) }.compact.uniq,
          tracking: lines.flat_map { |l| l.tracking_selections.map { |s| s.tracking_option&.name } }.compact.uniq)
    end

    # From an account and option ids, with names looked up in the given map.
    def self.of(account:, tracking_option_ids:, option_names:)
      new(accounts: [ display(account) ].compact,
          tracking: Array(tracking_option_ids).filter_map { |id| option_names[id] })
    end

    def self.display(account)
      return nil unless account
      [ account.code, account.name ].compact_blank.join(" ")
    end
  end

  # What a document's lines must have loaded for Coding.of_document to add no queries.
  # (Set outside the block: a constant inside Struct.new's block lands on the enclosing module.)
  Coding::LINE_PRELOAD = { line_items: [ :account, { tracking_selections: :tracking_option } ] }.freeze
end

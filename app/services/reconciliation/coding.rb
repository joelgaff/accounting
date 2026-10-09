module Reconciliation
  # The account and tracking behind a document or a suggested coding, as the
  # names a reader recognises, for the chips on a reconcile card.
  Coding = Struct.new(:accounts, :tracking, keyword_init: true) do
    def any? = accounts.any? || tracking.any?

    def self.of_document(document)
      lines = document.line_items.to_a
      new(accounts: lines.map { |l| display(l.account) }.compact.uniq,
          tracking: lines.flat_map { |l| l.tracking_selections.map { |s| tag(s.tracking_option) } }.compact.uniq)
    end

    # From an account and option ids, with the options looked up in the given map (id → option).
    def self.of(account:, tracking_option_ids:, options:)
      new(accounts: [ display(account) ].compact,
          tracking: Array(tracking_option_ids).filter_map { |id| tag(options[id]) })
    end

    def self.tag(option) = option && Coding::Tag.new(name: option.name, color: option.color)

    def self.display(account)
      return nil unless account
      [ account.code, account.name ].compact_blank.join(" ")
    end
  end

  # A tracking chip: the option's name in its colour.
  Coding::Tag = Struct.new(:name, :color, keyword_init: true)

  # What a document's lines must have loaded for Coding.of_document to add no queries.
  # (Set outside the block: a constant inside Struct.new's block lands on the enclosing module.)
  Coding::LINE_PRELOAD = { line_items: [ :account, { tracking_selections: :tracking_option } ] }.freeze
end

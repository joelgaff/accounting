# The interface every document type implements. Document calls these; the
# type never touches the ledger or the totals itself.
#
#   totals_for(document)        -> [subtotal, tax_amount]
#   ledger_legs(document)       -> { debits: [{ account:, amount: }], credits: [...] }
#   ledger_description(document)
#   status                      -> string used as the badge
#   party_name                  -> fallback when the document has no contact
#   line_items?                 -> false for types that carry their own lines
#   settleable?                 -> true for types that take payments; those also
#                                  implement settlement_legs(bank_account) and
#                                  settlement_direction (:received | :made)
module Documentable
  extend ActiveSupport::Concern

  included do
    has_one :document, as: :documentable, inverse_of: :documentable, touch: true
  end

  def line_items? = true
  def settleable? = false
  def party_name  = nil

  def totals_for(document)
    [ document.line_items_subtotal, document.line_items_tax ]
  end

  def ledger_legs(_document)        = raise(NotImplementedError, "#{self.class} must define ledger_legs")
  def ledger_description(_document) = raise(NotImplementedError, "#{self.class} must define ledger_description")
  def status                        = "posted"
end

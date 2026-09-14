module Reconciliation
  # What a reconcile action changed: the line itself and, for transfers,
  # the mirror line that was linked along with it.
  Result = Struct.new(:transaction, :sibling, keyword_init: true)
end

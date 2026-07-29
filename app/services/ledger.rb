class Ledger
  class MissingAccount < StandardError; end

  def self.post(description:, commercial_document:, debits:, credits:, date: Date.current)
    ActiveRecord::Base.transaction do
      Plutus::Entry.create!(
        description: description,
        date: date,
        commercial_document: commercial_document,
        debits: debits,
        credits: credits
      )
    end
  end

  def self.scope
    Plutus::Account.where(tenant: Current.organization)
  end

  def self.lookup(name)
    scope.find_by(name: name)
  end

  def self.lookup!(name)
    lookup(name) || raise(MissingAccount, "No account named #{name.inspect} for org #{Current.organization&.id}")
  end

  def self.balance(name)
    lookup(name)&.balance || BigDecimal("0")
  end

  # Wipes every ledger entry (and its amounts) attached to the given
  # commercial document. Used when re-posting after an import updates
  # an existing invoice/expense in place. Plutus doesn't cascade
  # entry → amounts, so we do it ourselves.
  def self.reset_for(commercial_document)
    entry_ids = commercial_document.entries.pluck(:id)
    return if entry_ids.empty?
    Plutus::Amount.where(entry_id: entry_ids).delete_all
    Plutus::Entry.where(id: entry_ids).delete_all
  end
end

class Ledger
  class MissingAccount < StandardError; end

  def self.post(description:, commercial_document:, debits:, credits:)
    ActiveRecord::Base.transaction do
      Plutus::Entry.create!(
        description: description,
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
end

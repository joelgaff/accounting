# A ledger account may be the face of one bank account (see BankAccount).
Rails.application.config.to_prepare do
  Plutus::Account.has_one :bank_account, dependent: :destroy unless Plutus::Account.reflect_on_association(:bank_account)
end

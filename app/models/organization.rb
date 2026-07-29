class Organization < ApplicationRecord
  has_many :users,    dependent: :destroy
  has_many :contacts,  dependent: :destroy
  has_many :invoices,  dependent: :restrict_with_error
  has_many :expenses,  dependent: :restrict_with_error
  has_many :tax_rates,          dependent: :destroy
  has_many :bank_transactions,  dependent: :destroy
  has_many :journal_entries,    dependent: :destroy
  has_one  :settings, class_name: "OrganizationSettings", dependent: :destroy
  validates :name, presence: true

  def plutus_accounts
    Plutus::Account.where(tenant: self)
  end

  def settings
    super || build_settings
  end
end

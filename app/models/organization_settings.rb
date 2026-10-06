class OrganizationSettings < ApplicationRecord
  belongs_to :organization
  belongs_to :bank_account,       optional: true
  belongs_to :receivable_account, class_name: "Plutus::Asset",     optional: true
  belongs_to :payable_account,    class_name: "Plutus::Liability", optional: true

  scoped_to_organization :bank_account, :receivable_account, :payable_account, organization: ->(s) { s.organization }
end

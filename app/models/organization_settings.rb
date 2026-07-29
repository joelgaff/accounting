class OrganizationSettings < ApplicationRecord
  belongs_to :organization
  belongs_to :bank_account,       class_name: "Plutus::Asset",     optional: true
  belongs_to :receivable_account, class_name: "Plutus::Asset",     optional: true
  belongs_to :payable_account,    class_name: "Plutus::Liability", optional: true
end

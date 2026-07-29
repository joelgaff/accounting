class TaxRate < ApplicationRecord
  belongs_to :organization
  belongs_to :liability_account, class_name: "Plutus::Liability", optional: true
  belongs_to :asset_account,     class_name: "Plutus::Asset",     optional: true

  validates :name, presence: true, uniqueness: { scope: :organization_id }
  validates :rate, numericality: { greater_than_or_equal_to: 0, less_than: 1 }

  scope :ordered, -> { order(:name) }

  # Xero's tax types:
  #   OUTPUT / OUTPUT2 ... = sales tax we collect (owed to gov)
  #   INPUT  / INPUT2  ... = purchase tax we pay (recoverable)
  #   NONE / EXEMPTOUTPUT / EXEMPTINPUT / GSTONIMPORTS / BASEXCLUDED
  def sales?     = xero_tax_type.to_s.start_with?("OUTPUT")   || liability_account.present?
  def purchase?  = xero_tax_type.to_s.start_with?("INPUT")    || asset_account.present?
  def zero?      = rate.zero?
end

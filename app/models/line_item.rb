class LineItem < ApplicationRecord
  belongs_to :lineable, polymorphic: true
  belongs_to :account,  class_name: "Plutus::Account"
  belongs_to :tax_rate, optional: true

  validates :description, presence: true, allow_blank: true   # empty OK, just no nil
  validates :quantity,    numericality: { greater_than: 0 }
  validates :unit_amount, numericality: true

  scope :ordered, -> { order(:position, :id) }

  def amount    = (quantity * unit_amount).round(2)
  def tax_total = tax_rate ? (amount * tax_rate.rate).round(2) : BigDecimal("0")
  def gross     = amount + tax_total
end

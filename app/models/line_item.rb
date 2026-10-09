class LineItem < ApplicationRecord
  include Trackable

  belongs_to :lineable, polymorphic: true
  belongs_to :account,  class_name: "Plutus::Account"
  belongs_to :tax_rate, optional: true

  validates :description, presence: true, allow_blank: true   # empty OK, just no nil
  validates :quantity,    numericality: { greater_than: 0 }
  validates :unit_amount, numericality: true

  scope :ordered, -> { order(:position, :id) }

  # Nil-safe: totals are computed before validation gets a chance to reject a blank field.
  scoped_to_organization :account, :tax_rate, organization: ->(line) { line.lineable&.organization }

  # A new, unsaved line like this one on another document or template, tracking included.
  def copy_to(lineable)
    line = lineable.line_items.build(description: description, quantity: quantity, unit_amount: unit_amount,
                                     account: account, tax_rate: tax_rate)
    copy_tracking_to(line)
    line
  end

  def amount    = (quantity.to_d * unit_amount.to_d).round(2)
  def tax_total = tax_rate ? (amount * tax_rate.rate).round(2) : BigDecimal("0")
  def gross     = amount + tax_total
end

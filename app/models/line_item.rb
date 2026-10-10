class LineItem < ApplicationRecord
  include Trackable

  belongs_to :lineable, polymorphic: true
  belongs_to :account,  class_name: "Plutus::Account"
  belongs_to :tax_rate, optional: true
  belongs_to :rebills, class_name: "Document", foreign_key: :rebills_document_id, optional: true, inverse_of: :rebilling_lines   # the billable cost this invoice line picks up

  validates :description, presence: true, allow_blank: true   # empty OK, just no nil
  validates :quantity,    numericality: { greater_than: 0 }
  validates :unit_amount, numericality: true

  validate :rebills_a_billable_cost, if: :rebills

  scope :ordered, -> { order(:position, :id) }
  # Lines on live invoices that pick up a cost: the set of costs that are billed.
  scope :rebilling, -> {
    where.not(rebills_document_id: nil).where(lineable_type: "Document")
         .joins("INNER JOIN documents invoices ON invoices.id = line_items.lineable_id")
         .where(invoices: { voided_at: nil, documentable_type: "Invoice" })
  }

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

  private

  # Only an invoice line rebills, only a cost flagged for a customer of this
  # organisation, and only once while another live invoice holds it.
  def rebills_a_billable_cost
    invoice = lineable
    unless invoice.is_a?(Document) && invoice.invoice?
      return errors.add(:rebills, "only an invoice line can rebill a cost")
    end
    unless rebills.billable? && rebills.billable_to && rebills.organization_id == invoice.organization_id
      return errors.add(:rebills, "is not a cost flagged as billable")
    end
    elsewhere = rebills.billed_on
    errors.add(:rebills, "is already billed on #{elsewhere.label}") if elsewhere && elsewhere != invoice
  end
end

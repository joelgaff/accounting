# Polymorphic line items with live totals. Computed names are prefixed so they
# never shadow the subtotal/tax_amount/total columns a document stores.
module HasLineItems
  extend ActiveSupport::Concern

  included do
    has_many :line_items, -> { ordered }, as: :lineable, dependent: :destroy, inverse_of: :lineable
    accepts_nested_attributes_for :line_items, allow_destroy: true, reject_if: :all_blank
  end

  def live_line_items    = line_items.reject(&:marked_for_destruction?)
  def line_items_subtotal = live_line_items.sum(&:amount)
  def line_items_tax      = live_line_items.sum(&:tax_total)
  def line_items_total    = line_items_subtotal + line_items_tax

  # { accounts: { account => net }, taxes: { tax_rate => tax } }
  def line_ledger_legs
    by_account = live_line_items.group_by(&:account).transform_values { |lis| lis.sum(&:amount) }
    by_tax     = live_line_items.select { |li| li.tax_rate && li.tax_total.positive? }
                                .group_by(&:tax_rate)
                                .transform_values { |lis| lis.sum(&:tax_total) }
    { accounts: by_account, taxes: by_tax }
  end
end

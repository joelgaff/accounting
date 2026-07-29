module HasLineItems
  extend ActiveSupport::Concern

  included do
    has_many :line_items, -> { ordered }, as: :lineable, dependent: :destroy, inverse_of: :lineable
    accepts_nested_attributes_for :line_items, allow_destroy: true, reject_if: :all_blank
  end

  def subtotal   = line_items.sum(&:amount)
  def tax_amount = line_items.sum(&:tax_total)
  def total      = subtotal + tax_amount

  # Group legs for the ledger post — one credit/debit per revenue/expense account,
  # one liability credit or asset debit per tax rate.
  def line_ledger_legs
    by_account = line_items.group_by(&:account).transform_values { |lis| lis.sum(&:amount) }
    by_tax     = line_items.select { |li| li.tax_rate && li.tax_total.positive? }
                            .group_by(&:tax_rate)
                            .transform_values { |lis| lis.sum(&:tax_total) }
    { accounts: by_account, taxes: by_tax }
  end
end

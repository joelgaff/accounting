# One option from one category, pinned to a line (or a bank rule that will
# create lines). The category is stored alongside the option so "one per
# category" is a database rule.
class TrackingSelection < ApplicationRecord
  belongs_to :trackable, polymorphic: true
  belongs_to :tracking_category
  belongs_to :tracking_option

  before_validation { self.tracking_category ||= tracking_option&.tracking_category }
  validates :tracking_category_id, uniqueness: { scope: %i[trackable_type trackable_id] }
  validate  :option_belongs_to_category

  private

  def option_belongs_to_category
    return if tracking_option.nil? || tracking_category.nil? || tracking_option.tracking_category_id == tracking_category_id
    errors.add(:tracking_option, "does not belong to #{tracking_category.name}")
  end
end

# A dimension to slice the books by, such as "Event Year" or "Class". Like
# Xero, at most two can be active at once so line rows stay readable.
class TrackingCategory < ApplicationRecord
  MAX_ACTIVE = 2

  belongs_to :organization
  has_many :options, -> { order(:position, :name) }, class_name: "TrackingOption", inverse_of: :tracking_category, dependent: :destroy
  has_many :selections, class_name: "TrackingSelection", dependent: :destroy
  accepts_nested_attributes_for :options, allow_destroy: true, reject_if: ->(attrs) { attrs["name"].blank? }

  validates :name, presence: true, uniqueness: { scope: :organization_id }
  validate  :at_most_two_active

  scope :active,  -> { where(active: true) }
  scope :ordered, -> { order(:position, :name) }

  def active_options = options.select(&:active?)

  private

  def at_most_two_active
    return unless active?
    others = organization.tracking_categories.active.where.not(id: id).count
    errors.add(:active, "— only #{MAX_ACTIVE} categories can be active at once") if others >= MAX_ACTIVE
  end
end

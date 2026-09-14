class TrackingOption < ApplicationRecord
  belongs_to :tracking_category, inverse_of: :options
  has_many   :selections, class_name: "TrackingSelection", dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { scope: :tracking_category_id }

  scope :active, -> { where(active: true) }

  def label = "#{tracking_category.name}: #{name}"
end

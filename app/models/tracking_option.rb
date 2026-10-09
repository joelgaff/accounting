# One value of a tracking category: "2026" under Event Year, "Summit Races"
# under Class. Each wears one of twelve colours so its chip is told apart
# at a glance; the palette goes round within a category and starts
# over in the next, so two categories can both hold an orange.
class TrackingOption < ApplicationRecord
  PALETTE_SIZE = 12

  belongs_to :tracking_category, inverse_of: :options
  has_many   :selections, class_name: "TrackingSelection", dependent: :restrict_with_error

  attribute :color, :integer, default: nil   # the column defaults to 0; nil here means "not chosen yet"

  before_validation :take_next_color, on: :create
  validates :name, presence: true, uniqueness: { scope: :tracking_category_id }
  validates :color, inclusion: { in: 0...PALETTE_SIZE }

  scope :active, -> { where(active: true) }

  def label = "#{tracking_category.name}: #{name}"

  private

  # The next slot after the category's other options, the unsaved ones before this included,
  # so a form that adds several at once colours them in order.
  def take_next_color
    return unless color.nil? && tracking_category
    siblings = tracking_category.options.to_a.reject { |o| o.equal?(self) || o.marked_for_destruction? }
    self.color = siblings.count { |o| o.persisted? || o.color } % PALETTE_SIZE
  end
end

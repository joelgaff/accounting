# Lines (and bank rules) carry one tracking option per category. Forms and
# importers hand over a list of option ids; the last one per category wins.
module Trackable
  extend ActiveSupport::Concern

  included do
    has_many :tracking_selections, as: :trackable, dependent: :destroy, inverse_of: :trackable, autosave: true
  end

  def tracking_options = tracking_selections.map(&:tracking_option)

  def tracking_option_ids
    tracking_selections.map(&:tracking_option_id)
  end

  def tracking_option_ids=(ids)
    wanted = TrackingOption.where(id: Array(ids).compact_blank).includes(:tracking_category).index_by(&:tracking_category_id)
    # Re-point an existing selection rather than replacing it, so the
    # one-per-category uniqueness check never trips over its own predecessor.
    tracking_selections.each do |s|
      option = wanted.delete(s.tracking_category_id)
      option ? s.tracking_option = option : s.mark_for_destruction
    end
    wanted.each_value { |option| tracking_selections.build(tracking_option: option, tracking_category: option.tracking_category) }
  end

  def tracking_option_for(category)
    tracking_selections.find { |s| s.tracking_category_id == category.id }&.tracking_option
  end

  # Copy this line's tracking onto another line (recurring invoices, rules).
  def copy_tracking_to(other)
    other.tracking_option_ids = tracking_option_ids
  end
end

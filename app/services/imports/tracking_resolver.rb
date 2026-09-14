module Imports
  # Xero exports carry tracking as TrackingName1/TrackingOption1 (and 2) on
  # every line. Categories and options are created on first sight, so a
  # bundle from Xero brings its tracking setup with it.
  class TrackingResolver
    def initialize(organization)
      @org   = organization
      @cache = {}
    end

    # Reads the pairs off a CSV row (headers already normalized) and returns option ids.
    def option_ids_for(row)
      (1..2).filter_map do |i|
        name   = row["trackingname#{i}"].to_s.strip
        option = row["trackingoption#{i}"].to_s.strip
        next if name.blank? || option.blank?
        resolve(name, option).id
      end
    end

    def resolve(category_name, option_name)
      @cache[[ category_name, option_name ]] ||= begin
        category = @org.tracking_categories.find_by("LOWER(name) = ?", category_name.downcase) ||
                   @org.tracking_categories.create!(name: category_name, active: @org.tracking_categories.active.count < TrackingCategory::MAX_ACTIVE,
                                                    position: (@org.tracking_categories.maximum(:position) || 0) + 1)
        category.options.find_by("LOWER(name) = ?", option_name.downcase) ||
          category.options.create!(name: option_name, position: (category.options.maximum(:position) || 0) + 1)
      end
    end
  end
end

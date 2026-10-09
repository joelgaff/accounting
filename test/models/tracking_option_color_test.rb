require "test_helper"

# Every tracking option has a colour, so its chip is told apart at a glance.
# Colours go round a short palette within a category; categories start over,
# so two categories can both hold an orange chip.
class TrackingOptionColorTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
  end

  test "twelve colours, taken in order within a category, then round again" do
    assert_equal 12, TrackingOption::PALETTE_SIZE
    year = @org.tracking_categories.create!(name: "Event Year", options_attributes: (2010..2023).map { |y| { name: y.to_s } })
    assert_equal (0...12).to_a + [ 0, 1 ], year.options.map(&:color)
  end

  test "a second category starts the palette over" do
    @org.tracking_categories.create!(name: "Event Year", options_attributes: [ { name: "2025" }, { name: "2026" } ])
    klass = @org.tracking_categories.create!(name: "Class", options_attributes: [ { name: "EE Timing" }, { name: "Summit Races" } ])
    assert_equal [ 0, 1 ], klass.options.map(&:color)
  end

  test "an option added later takes the next colour, and a given colour is kept" do
    year = @org.tracking_categories.create!(name: "Event Year", options_attributes: [ { name: "2025" }, { name: "2026" } ])
    later = year.options.create!(name: "2027")
    assert_equal 2, later.color
    chosen = year.options.create!(name: "2028", color: 5)
    assert_equal 5, chosen.color
    assert_not year.options.build(name: "2029", color: TrackingOption::PALETTE_SIZE).valid?, "off the palette"
  end
end

# Xero-style tracking: up to two active categories per organisation (say
# "Event Year" and "Class"), options under each, and one option per category
# assigned to any line — document line items, journal lines, and bank rules
# that create lines.
class CreateTrackingCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :tracking_categories do |t|
      t.references :organization, null: false, foreign_key: true
      t.string  :name, null: false
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.timestamps
      t.index %i[organization_id name], unique: true
    end

    create_table :tracking_options do |t|
      t.references :tracking_category, null: false, foreign_key: true
      t.string  :name, null: false
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.timestamps
      t.index %i[tracking_category_id name], unique: true
    end

    create_table :tracking_selections do |t|
      t.references :trackable, polymorphic: true, null: false
      t.references :tracking_category, null: false, foreign_key: true
      t.references :tracking_option,   null: false, foreign_key: true
      t.timestamps
      t.index %i[trackable_type trackable_id tracking_category_id], unique: true, name: "idx_tracking_selections_one_per_category"
      t.index %i[tracking_option_id trackable_type], name: "idx_tracking_selections_by_option"
    end
  end
end

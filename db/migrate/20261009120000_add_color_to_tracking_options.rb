class AddColorToTrackingOptions < ActiveRecord::Migration[8.1]
  def up
    add_column :tracking_options, :color, :integer, null: false, default: 0
    # Existing options take the palette in their category's order, as new ones will.
    execute <<~SQL
      UPDATE tracking_options SET color = (
        SELECT COUNT(*) FROM tracking_options AS earlier
        WHERE earlier.tracking_category_id = tracking_options.tracking_category_id
          AND (earlier.position < tracking_options.position
               OR (earlier.position = tracking_options.position AND earlier.id < tracking_options.id))
      ) % 12
    SQL
  end

  def down
    remove_column :tracking_options, :color
  end
end

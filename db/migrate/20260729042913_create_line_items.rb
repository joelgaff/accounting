class CreateLineItems < ActiveRecord::Migration[8.1]
  def change
    create_table :line_items do |t|
      t.references :lineable, polymorphic: true, null: false
      t.references :account,  null: false     # FK to plutus_accounts
      t.references :tax_rate                    # optional
      t.string  :description, null: false, default: ""
      t.decimal :quantity,    precision: 10, scale: 4, default: 1, null: false
      t.decimal :unit_amount, precision: 20, scale: 4, null: false
      t.integer :position,    default: 0, null: false
      t.timestamps
    end
    add_index :line_items, [:lineable_type, :lineable_id, :position]
  end
end

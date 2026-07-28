class CreateExpenses < ActiveRecord::Migration[8.1]
  def change
    create_table :expenses do |t|
      t.references :organization,           null: false, foreign_key: true
      t.references :expense_account,        null: false
      t.references :paid_from_account,      null: false
      t.string     :vendor,                 null: false
      t.decimal    :amount, precision: 20, scale: 2, null: false
      t.date       :incurred_on,            null: false
      t.text       :memo
      t.timestamps
    end
  end
end

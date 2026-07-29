class CreatePayments < ActiveRecord::Migration[8.1]
  def change
    create_table :payments do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :payable, polymorphic: true, null: false  # Invoice or Expense
      t.references :bank_account, null: false                # Plutus::Asset (money in/out)
      t.decimal    :amount, precision: 20, scale: 2, null: false
      t.date       :paid_on, null: false
      t.string     :reference
      t.text       :memo
      t.timestamps
    end
    add_index :payments, [:organization_id, :paid_on]
  end
end

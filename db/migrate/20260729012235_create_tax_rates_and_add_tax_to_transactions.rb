class CreateTaxRatesAndAddTaxToTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :tax_rates do |t|
      t.references :organization,  null: false, foreign_key: true
      t.string  :name,             null: false
      t.decimal :rate, precision: 6, scale: 4, null: false  # 0.0875 = 8.75%
      t.string  :xero_tax_type              # e.g. OUTPUT2, INPUT2, NONE
      t.references :liability_account,      null: true      # for output/sales tax (payable to gov)
      t.references :asset_account,          null: true      # for input/purchase tax (recoverable)
      t.timestamps
    end
    add_index :tax_rates, [:organization_id, :name], unique: true

    add_reference :invoices, :tax_rate, foreign_key: true
    add_column    :invoices, :subtotal,   :decimal, precision: 20, scale: 2
    add_column    :invoices, :tax_amount, :decimal, precision: 20, scale: 2, default: 0, null: false

    add_reference :expenses, :tax_rate, foreign_key: true
    add_column    :expenses, :subtotal,   :decimal, precision: 20, scale: 2
    add_column    :expenses, :tax_amount, :decimal, precision: 20, scale: 2, default: 0, null: false
  end
end

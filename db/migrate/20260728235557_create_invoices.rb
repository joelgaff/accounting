class CreateInvoices < ActiveRecord::Migration[8.1]
  def change
    create_table :invoices do |t|
      t.references :organization,          null: false, foreign_key: true
      t.references :receivable_account,    null: false
      t.references :revenue_account,       null: false
      t.string     :client_name,           null: false
      t.decimal    :amount, precision: 20, scale: 2, null: false
      t.date       :due_date,              null: false
      t.timestamps
    end
  end
end

class CreateRecurringInvoices < ActiveRecord::Migration[8.1]
  def change
    create_table :recurring_invoices do |t|
      t.references :organization,        null: false, foreign_key: true
      t.references :contact
      t.references :receivable_account,  null: false     # Plutus::Asset
      t.string     :client_name,         null: false
      t.integer    :net_days,            default: 30, null: false   # invoice due_date = generated_on + net_days
      t.string     :frequency,           null: false                # weekly | monthly | yearly
      t.integer    :interval,            default: 1, null: false
      t.date       :next_run_on,         null: false
      t.date       :end_on
      t.boolean    :active,              default: true, null: false
      t.boolean    :email_on_generate,   default: false, null: false
      t.timestamps
    end
    add_index :recurring_invoices, [:organization_id, :active, :next_run_on]
  end
end

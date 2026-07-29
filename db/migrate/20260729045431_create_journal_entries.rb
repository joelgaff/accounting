class CreateJournalEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :journal_entries do |t|
      t.references :organization, null: false, foreign_key: true
      t.date       :posted_on,    null: false
      t.string     :narrative,    null: false
      t.string     :reference
      t.timestamps
    end

    create_table :journal_lines do |t|
      t.references :journal_entry, null: false, foreign_key: true
      t.references :account,       null: false   # FK to plutus_accounts
      t.decimal    :debit_amount,  precision: 20, scale: 2, default: 0, null: false
      t.decimal    :credit_amount, precision: 20, scale: 2, default: 0, null: false
      t.string     :memo
      t.integer    :position, default: 0, null: false
      t.timestamps
    end
  end
end

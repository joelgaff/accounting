class CreateBankTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :bank_transactions do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :bank_account, null: false                    # Plutus::Asset
      t.references :matched, polymorphic: true                   # Payment | Expense | Invoice
      t.date       :posted_on, null: false
      t.text       :description
      t.string     :reference
      t.decimal    :amount, precision: 20, scale: 2, null: false # signed: +deposit / -withdrawal
      t.string     :status, null: false, default: "unmatched"
      t.timestamps
    end
    add_index :bank_transactions, [:organization_id, :bank_account_id, :posted_on, :amount, :description],
              unique: true, name: "idx_bank_txns_dedupe"
    add_index :bank_transactions, [:organization_id, :status]
  end
end

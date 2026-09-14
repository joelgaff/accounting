# Statement lines link straight to what settles them: payments carry the line
# they came from, a line may carry one document (expense, deposit, transfer),
# and a line remembers the rule that suggested a category. Payee is kept apart
# from the description. Data is wipeable, so the old polymorphic match goes.
class ReconcileUpgrades < ActiveRecord::Migration[8.1]
  def change
    create_table :bank_rules do |t|
      t.references :organization, null: false, foreign_key: true
      t.string     :name, null: false
      t.integer    :position, null: false, default: 0
      t.string     :match_kind,  null: false, default: "contains"   # contains | starts_with | regex
      t.string     :pattern,     null: false
      t.string     :amount_sign, null: false, default: "any"        # any | in | out
      t.references :bank_account, foreign_key: true
      t.string     :action_kind, null: false                        # Expense | Deposit | Transfer
      t.references :contact,  foreign_key: true
      t.references :account,  foreign_key: { to_table: :plutus_accounts }
      t.references :tax_rate, foreign_key: true
      t.references :transfer_bank_account, foreign_key: { to_table: :bank_accounts }
      t.boolean    :auto_apply, null: false, default: false
      t.boolean    :active,     null: false, default: true
      t.timestamps
      t.index %i[organization_id position]
    end

    remove_index  :bank_transactions, name: "idx_bank_txns_dedupe"
    remove_index  :bank_transactions, name: "index_bank_transactions_on_matched"
    remove_column :bank_transactions, :matched_type, :string
    remove_column :bank_transactions, :matched_id, :integer
    add_column    :bank_transactions, :payee, :string, null: false, default: ""
    add_reference :bank_transactions, :document,  foreign_key: true
    add_reference :bank_transactions, :bank_rule, foreign_key: true
    add_index     :bank_transactions, %i[organization_id bank_account_id posted_on amount payee description],
                  name: "idx_bank_txns_dedupe", unique: true

    add_reference :payments, :bank_transaction, foreign_key: true

    add_column :bank_accounts, :statement_balance,    :decimal, precision: 20, scale: 2
    add_column :bank_accounts, :statement_balance_at, :datetime
  end
end

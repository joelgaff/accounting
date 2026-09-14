class CreateDepositsAndTransfers < ActiveRecord::Migration[8.1]
  def change
    create_table :deposits do |t|
      t.references :bank_account, null: false, foreign_key: true
      t.timestamps
    end

    create_table :transfers do |t|
      t.references :from_bank_account, null: false, foreign_key: { to_table: :bank_accounts }
      t.references :to_bank_account,   null: false, foreign_key: { to_table: :bank_accounts }
      t.timestamps
    end

    # Where a document came from: manual | reconcile | xero_import. Undo on the
    # reconcile page removes what it created and only unlinks what a person made.
    add_column :documents, :source, :string, null: false, default: "manual"
  end
end

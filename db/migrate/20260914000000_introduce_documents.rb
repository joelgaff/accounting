# Rebuilds the transaction tables under a Document superclass (delegated types).
# By agreement the books are re-imported from the Xero bundle after this lands,
# so transactional data is discarded here rather than migrated. The chart of
# accounts, bank accounts, contacts, tax rates, settings and users are untouched.
class IntroduceDocuments < ActiveRecord::Migration[8.1]
  def up
    execute "DELETE FROM plutus_amounts"
    execute "DELETE FROM plutus_entries"
    execute "DELETE FROM line_items WHERE lineable_type IN ('Invoice', 'Expense')"
    execute "DELETE FROM active_storage_attachments WHERE record_type IN ('Invoice', 'Expense')"
    execute "UPDATE bank_transactions SET matched_type = NULL, matched_id = NULL, status = 'unmatched'"

    drop_table :payments
    drop_table :journal_lines
    drop_table :journal_entries
    drop_table :expenses
    drop_table :invoices

    create_table :documents do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :contact, foreign_key: true
      t.references :documentable, polymorphic: true, null: false, index: { unique: true }
      t.date       :date, null: false
      t.string     :reference
      t.text       :memo
      t.decimal    :subtotal,   precision: 20, scale: 2, null: false, default: 0
      t.decimal    :tax_amount, precision: 20, scale: 2, null: false, default: 0
      t.decimal    :total,      precision: 20, scale: 2, null: false, default: 0
      t.timestamps
      t.index %i[organization_id date]
      t.index %i[organization_id documentable_type date]
    end

    create_table :invoices do |t|
      t.string     :client_name, null: false
      t.date       :due_date, null: false
      t.references :receivable_account, null: false, foreign_key: { to_table: :plutus_accounts }
      t.string     :xero_invoice_number
      t.timestamps
      t.index :xero_invoice_number, unique: true, where: "xero_invoice_number IS NOT NULL"
    end

    create_table :bills do |t|
      t.string     :vendor, null: false
      t.references :payable_account, null: false, foreign_key: { to_table: :plutus_accounts }
      t.string     :xero_invoice_number
      t.timestamps
      t.index :xero_invoice_number, unique: true, where: "xero_invoice_number IS NOT NULL"
    end

    create_table :expenses do |t|
      t.string     :vendor, null: false
      t.references :bank_account, null: false, foreign_key: true
      t.timestamps
    end

    create_table :journal_entries do |t|
      t.string :narrative, null: false
      t.string :xero_journal_number
      t.string :xero_source_type
      t.timestamps
      t.index :xero_journal_number, unique: true, where: "xero_journal_number IS NOT NULL", name: "idx_journal_entries_xero_number"
    end

    create_table :journal_lines do |t|
      t.references :journal_entry, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: { to_table: :plutus_accounts }
      t.decimal    :debit_amount,  precision: 20, scale: 2, null: false, default: 0
      t.decimal    :credit_amount, precision: 20, scale: 2, null: false, default: 0
      t.string     :memo
      t.integer    :position, null: false, default: 0
      t.timestamps
    end

    create_table :payments do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :document, null: false, foreign_key: true
      t.references :bank_account, null: false, foreign_key: true
      t.decimal    :amount, precision: 20, scale: 2, null: false
      t.date       :paid_on, null: false
      t.string     :reference
      t.text       :memo
      t.timestamps
      t.index %i[organization_id paid_on]
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end

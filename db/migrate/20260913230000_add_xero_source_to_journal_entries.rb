class AddXeroSourceToJournalEntries < ActiveRecord::Migration[8.0]
  def change
    add_column :journal_entries, :xero_journal_number, :string
    add_column :journal_entries, :xero_source_type,    :string
    add_index  :journal_entries, [ :organization_id, :xero_journal_number ], unique: true,
               where: "xero_journal_number IS NOT NULL", name: "idx_journal_entries_xero_number"
  end
end

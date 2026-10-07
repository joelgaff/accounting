class AddStateToDocuments < ActiveRecord::Migration[8.1]
  def change
    # Everything already in the books has posted to the ledger, so it is approved.
    add_column :documents, :state, :string, null: false, default: "approved"
    add_index  :documents, [ :organization_id, :state ]
  end
end

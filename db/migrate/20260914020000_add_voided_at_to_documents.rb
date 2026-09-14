class AddVoidedAtToDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :documents, :voided_at, :datetime
    add_index  :documents, %i[organization_id voided_at]
  end
end

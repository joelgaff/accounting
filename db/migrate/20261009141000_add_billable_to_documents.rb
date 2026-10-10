class AddBillableToDocuments < ActiveRecord::Migration[8.1]
  def change
    add_reference :documents, :billable_to, foreign_key: { to_table: :contacts }, null: true
  end
end

class AddRebillsDocumentToLineItems < ActiveRecord::Migration[8.1]
  def change
    add_reference :line_items, :rebills_document, foreign_key: { to_table: :documents }, null: true
  end
end

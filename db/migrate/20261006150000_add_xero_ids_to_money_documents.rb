class AddXeroIdsToMoneyDocuments < ActiveRecord::Migration[8.1]
  def change
    %i[expenses deposits transfers].each do |table|
      add_column table, :xero_id, :string
      add_index  table, :xero_id, unique: true, where: "xero_id IS NOT NULL"
    end
  end
end

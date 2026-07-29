class AddMetadataToPlutusAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :plutus_accounts, :code,        :string
    add_column :plutus_accounts, :description, :text
    add_column :plutus_accounts, :xero_type,   :string

    add_index  :plutus_accounts, [:tenant_id, :code], unique: true, where: "code IS NOT NULL"
  end
end

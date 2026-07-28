class TenantPlutusTables < ActiveRecord::Migration[8.1]
  def change
    add_column :plutus_accounts, :tenant_id, :integer
    add_index  :plutus_accounts, :tenant_id
  end
end

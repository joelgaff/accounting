class CreateOrganizationSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :organization_settings do |t|
      t.references :organization,        null: false, foreign_key: true, index: { unique: true }
      t.references :bank_account
      t.references :receivable_account
      t.references :payable_account
      t.timestamps
    end
  end
end

class AddBillableIncomeAccountToOrganizationSettings < ActiveRecord::Migration[8.1]
  def change
    add_reference :organization_settings, :billable_income_account, foreign_key: { to_table: :plutus_accounts }, null: true
  end
end

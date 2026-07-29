class RelaxTopLevelAccountNulls < ActiveRecord::Migration[8.1]
  def change
    change_column_null :invoices, :revenue_account_id, true
    change_column_null :expenses, :expense_account_id, true
  end
end

class AddContactToInvoicesAndExpenses < ActiveRecord::Migration[8.1]
  def change
    add_reference :invoices, :contact, foreign_key: true
    add_reference :expenses, :contact, foreign_key: true
  end
end

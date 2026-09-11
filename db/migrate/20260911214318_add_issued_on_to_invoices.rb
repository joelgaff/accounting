class AddIssuedOnToInvoices < ActiveRecord::Migration[8.1]
  def up
    add_column :invoices, :issued_on, :date
    # Until now the issue date was implicit in created_at; carry it over so the
    # ledger keeps posting existing invoices on the day they were raised.
    execute "UPDATE invoices SET issued_on = date(created_at) WHERE issued_on IS NULL"
    change_column_null :invoices, :issued_on, false
    add_index :invoices, [ :organization_id, :issued_on ]
  end

  def down
    remove_index  :invoices, [ :organization_id, :issued_on ]
    remove_column :invoices, :issued_on
  end
end

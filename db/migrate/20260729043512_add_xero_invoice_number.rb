class AddXeroInvoiceNumber < ActiveRecord::Migration[8.1]
  def change
    add_column :invoices, :xero_invoice_number, :string
    add_column :invoices, :reference,           :string
    add_index  :invoices, [:organization_id, :xero_invoice_number], unique: true, where: "xero_invoice_number IS NOT NULL"

    add_column :expenses, :xero_invoice_number, :string
    add_column :expenses, :reference,           :string
    add_index  :expenses, [:organization_id, :xero_invoice_number], unique: true, where: "xero_invoice_number IS NOT NULL"
  end
end

class AddNumbersToInvoicesAndBills < ActiveRecord::Migration[8.1]
  def up
    add_column :invoices, :number, :string
    add_column :bills,    :number, :string
    add_index  :invoices, :number, unique: true, where: "number IS NOT NULL"

    # Imported documents show the number Xero gave them; bills whose Xero
    # number was made up by the importer stay unnumbered.
    execute "UPDATE invoices SET number = xero_invoice_number WHERE xero_invoice_number IS NOT NULL"
    execute "UPDATE bills SET number = xero_invoice_number WHERE xero_invoice_number IS NOT NULL AND xero_invoice_number NOT LIKE 'XERO-%'"

    # Hand-made invoices continue the sequence after the highest Xero number.
    Document.reset_column_information
    Organization.find_each do |org|
      Invoice.joins(:document).where(documents: { organization_id: org.id }, number: nil).order(:id).each do |invoice|
        invoice.update_columns(number: Invoice.next_number(org))
      end
    end
  end

  def down
    remove_index  :invoices, :number
    remove_column :invoices, :number
    remove_column :bills,    :number
  end
end

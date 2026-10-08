class AddInvoiceNumberingToOrganizationSettings < ActiveRecord::Migration[8.1]
  def change
    # The prefix is the organisation's own. A nil next number means "follow
    # the highest invoice already carrying the prefix", so nothing changes on
    # deploy until someone sets it or saves an invoice.
    add_column :organization_settings, :invoice_prefix, :string, null: false, default: "INV-"
    add_column :organization_settings, :invoice_next_number, :integer
  end
end

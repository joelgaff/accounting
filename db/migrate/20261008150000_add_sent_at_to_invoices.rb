class AddSentAtToInvoices < ActiveRecord::Migration[8.1]
  def change
    # When the invoice went to the customer: emailed from here, or marked sent by hand.
    add_column :invoices, :sent_at, :datetime
  end
end

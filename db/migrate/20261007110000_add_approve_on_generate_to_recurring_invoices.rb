class AddApproveOnGenerateToRecurringInvoices < ActiveRecord::Migration[8.1]
  def change
    # Existing templates keep posting what they generate; drafts are opt-in per template.
    add_column :recurring_invoices, :approve_on_generate, :boolean, null: false, default: true
  end
end

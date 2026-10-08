class AddHiddenReconcileCardIdsToUsers < ActiveRecord::Migration[8.1]
  def change
    # Which bank accounts' summary cards this person has tucked away on the reconcile page.
    add_column :users, :hidden_reconcile_card_ids, :json, null: false, default: []
  end
end

class AddPendingEmailToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :pending_email_address, :string   # a new address awaiting its confirmation code
  end
end

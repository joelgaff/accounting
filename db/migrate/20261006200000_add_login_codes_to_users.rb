class AddLoginCodesToUsers < ActiveRecord::Migration[8.1]
  def change
    change_column_null :users, :launchpad_public_id, true
    add_column :users, :login_code_digest,     :string
    add_column :users, :login_code_expires_at, :datetime
    add_column :users, :login_code_attempts,   :integer, null: false, default: 0
    add_column :users, :login_code_sent_at,    :datetime
    add_column :users, :login_code_sends,      :integer, null: false, default: 0
    # Local sign-in finds people by email; hub-synced users are found by their
    # Launchpad id and may share an address across ids.
    add_index :users, "LOWER(email_address)", unique: true, where: "launchpad_public_id IS NULL", name: "index_users_on_lower_email_for_local_sign_in"
  end
end

class ConvertUsersToLaunchpadSso < ActiveRecord::Migration[8.1]
  # Auth moves to the Launchpad SSO hub. A user is now identified by the hub's
  # stable public_id and carries synced display fields; the local Identity
  # (and its login-code columns) goes away entirely.
  def up
    add_column :users, :launchpad_public_id, :string
    add_column :users, :email_address,       :string

    # Preserve display email for any existing rows before the identities table drops.
    execute <<~SQL
      UPDATE users
      SET email_address = (SELECT email FROM identities WHERE identities.id = users.identity_id)
      WHERE identity_id IS NOT NULL
    SQL

    add_index :users, :launchpad_public_id, unique: true

    remove_foreign_key :users, :identities
    remove_column :users, :identity_id, :integer
    drop_table :identities do |t|
      t.string   :email
      t.string   :login_code_digest
      t.datetime :login_code_expires_at
      t.timestamps
    end
  end

  def down
    create_table :identities do |t|
      t.string   :email
      t.string   :login_code_digest
      t.datetime :login_code_expires_at
      t.timestamps
    end
    add_reference :users, :identity, foreign_key: true
    remove_index  :users, :launchpad_public_id
    remove_column :users, :email_address
    remove_column :users, :launchpad_public_id
  end
end

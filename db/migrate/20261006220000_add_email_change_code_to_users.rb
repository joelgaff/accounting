class AddEmailChangeCodeToUsers < ActiveRecord::Migration[8.1]
  # The email-change code lives apart from the sign-in code, so a sign-in code
  # sent to the current address can never confirm a move to a new one.
  def change
    add_column :users, :pending_email_code_digest, :string
    add_column :users, :pending_email_expires_at,  :datetime
  end
end

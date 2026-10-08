class AddEmailSenderToOrganizationSettings < ActiveRecord::Migration[8.1]
  def change
    # The name mail goes out under (nil: the organisation's name) and where replies land.
    add_column :organization_settings, :email_from_name, :string
    add_column :organization_settings, :email_reply_to,  :string
  end
end

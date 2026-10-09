class RenameContactsCompanyNumberToAccountNumber < ActiveRecord::Migration[8.1]
  # Xero's AccountNumber was landing here under a name nothing displayed. It
  # is the number the contact knows you by, so it is called that now.
  def change
    rename_column :contacts, :company_number, :account_number
  end
end

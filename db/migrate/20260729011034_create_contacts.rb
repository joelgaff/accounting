class CreateContacts < ActiveRecord::Migration[8.1]
  def change
    create_table :contacts do |t|
      t.references :organization, null: false, foreign_key: true
      t.string  :name,            null: false
      t.string  :kind,            null: false, default: "both"  # customer | vendor | both
      t.string  :email
      t.string  :phone
      t.string  :first_name
      t.string  :last_name
      t.string  :company_number
      t.string  :tax_number
      t.text    :address
      t.string  :city
      t.string  :region
      t.string  :postal_code
      t.string  :country
      t.text    :notes
      t.timestamps
    end
    add_index :contacts, [:organization_id, :name]
  end
end

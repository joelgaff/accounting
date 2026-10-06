class CreateXeroConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :xero_connections do |t|
      t.references :organization, null: false, foreign_key: true, index: { unique: true }
      t.string   :tenant_id,     null: false
      t.string   :tenant_name
      t.text     :access_token,  null: false
      t.text     :refresh_token, null: false
      t.datetime :token_expires_at, null: false
      t.string   :status,        null: false, default: "idle"
      t.date     :import_from
      t.datetime :started_at
      t.datetime :last_import_at
      t.text     :progress
      t.text     :last_summary
      t.text     :last_error
      t.timestamps
    end
  end
end

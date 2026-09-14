# A bank feed is a credential with a lifecycle of its own (claimed, synced,
# errored, disconnected), so it gets a table rather than a Settings column.
# Feed and OFX lines carry the bank's own transaction id; only id-less CSV
# rows fall back to the composite dedupe.
class CreateBankFeeds < ActiveRecord::Migration[8.1]
  def change
    create_table :bank_feeds do |t|
      t.references :organization, null: false, foreign_key: true
      t.string   :provider, null: false, default: "simplefin"
      t.text     :access_url, null: false
      t.json     :accounts, null: false, default: []
      t.datetime :last_synced_at
      t.text     :last_error
      t.text     :last_summary
      t.timestamps
      t.index %i[organization_id provider], unique: true
    end

    add_reference :bank_accounts, :bank_feed, foreign_key: true
    add_column    :bank_accounts, :feed_account_id, :string
    add_column    :bank_accounts, :feed_name, :string
    add_column    :bank_accounts, :feed_synced_at, :datetime
    add_index     :bank_accounts, %i[bank_feed_id feed_account_id], unique: true, where: "feed_account_id IS NOT NULL"

    add_column :bank_transactions, :external_id, :string
    add_index  :bank_transactions, %i[bank_account_id external_id], unique: true, where: "external_id IS NOT NULL"
    remove_index :bank_transactions, name: "idx_bank_txns_dedupe"
    add_index  :bank_transactions, %i[organization_id bank_account_id posted_on amount payee description],
               name: "idx_bank_txns_dedupe", unique: true, where: "external_id IS NULL"
  end
end

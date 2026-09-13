class CreateBankAccounts < ActiveRecord::Migration[8.0]
  # A bank account is a chart-of-accounts entry plus the details only banks
  # carry (kind, institution, last four). Payments, bank transactions and the
  # Settings "operating bank" slot move from the ledger account to this record.
  REMAPPED = %w[payments bank_transactions organization_settings].freeze

  def up
    create_table :bank_accounts do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :account,      null: false, foreign_key: { to_table: :plutus_accounts }, index: { unique: true }
      t.string     :kind,         null: false, default: "checking"
      t.string     :institution
      t.string     :last_four
      t.datetime   :archived_at
      t.timestamps
    end

    referenced = REMAPPED.map { |tbl| "SELECT bank_account_id FROM #{tbl} WHERE bank_account_id IS NOT NULL" }.join(" UNION ")
    rows = select_all(<<~SQL)
      SELECT id, tenant_id, name FROM plutus_accounts
      WHERE tenant_id IS NOT NULL AND (xero_type = 'BANK' OR id IN (#{referenced}))
    SQL

    now = quote(Time.current)
    rows.each do |row|
      kind = case row["name"]
      when /card|visa|mastercard|amex/i then "credit_card"
      when /saving/i                     then "savings"
      else "checking"
      end
      execute <<~SQL
        INSERT INTO bank_accounts (organization_id, account_id, kind, created_at, updated_at)
        VALUES (#{row['tenant_id']}, #{row['id']}, #{quote(kind)}, #{now}, #{now})
      SQL
      execute "UPDATE plutus_accounts SET type = 'Plutus::Liability' WHERE id = #{row['id']}" if kind == "credit_card"
    end

    REMAPPED.each do |tbl|
      execute <<~SQL
        UPDATE #{tbl} SET bank_account_id = (SELECT id FROM bank_accounts WHERE account_id = #{tbl}.bank_account_id)
        WHERE bank_account_id IS NOT NULL
      SQL
    end
  end

  def down
    REMAPPED.each do |tbl|
      execute <<~SQL
        UPDATE #{tbl} SET bank_account_id = (SELECT account_id FROM bank_accounts WHERE id = #{tbl}.bank_account_id)
        WHERE bank_account_id IS NOT NULL
      SQL
    end
    execute "UPDATE plutus_accounts SET type = 'Plutus::Asset' WHERE id IN (SELECT account_id FROM bank_accounts WHERE kind = 'credit_card')"
    drop_table :bank_accounts
  end
end

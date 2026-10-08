class AddConditionsToBankRules < ActiveRecord::Migration[8.1]
  # A rule used to hold one text test in pattern and match_kind. Conditions
  # are rows now, several per rule, each on one field; every existing rule's
  # test becomes its first condition, so nothing changes on deploy.
  def up
    create_table :bank_rule_conditions do |t|
      t.references :bank_rule, null: false, foreign_key: true
      t.string  :field,    null: false
      t.string  :operator, null: false
      t.string  :value,    null: false
      t.string  :value_to
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_column :bank_rules, :match_all, :boolean, null: false, default: true

    execute <<~SQL
      INSERT INTO bank_rule_conditions (bank_rule_id, field, operator, value, position, created_at, updated_at)
      SELECT id, 'text', match_kind, pattern, 0, created_at, updated_at FROM bank_rules
    SQL
    remove_column :bank_rules, :pattern
    remove_column :bank_rules, :match_kind
  end

  def down
    add_column :bank_rules, :pattern, :string
    add_column :bank_rules, :match_kind, :string, default: "contains"
    execute <<~SQL
      UPDATE bank_rules SET
        pattern    = (SELECT value    FROM bank_rule_conditions c WHERE c.bank_rule_id = bank_rules.id ORDER BY position, id LIMIT 1),
        match_kind = (SELECT operator FROM bank_rule_conditions c WHERE c.bank_rule_id = bank_rules.id ORDER BY position, id LIMIT 1)
    SQL
    remove_column :bank_rules, :match_all
    drop_table :bank_rule_conditions
  end
end

class CreateDocumentEvents < ActiveRecord::Migration[8.1]
  def up
    create_table :document_events do |t|
      t.references :document,     null: false, foreign_key: true
      t.references :organization, null: false, foreign_key: true
      t.references :user,         null: true,  foreign_key: true
      t.string     :action,       null: false
      t.json       :details,      null: false, default: {}
      t.datetime   :created_at,   null: false
    end
    add_index :document_events, %i[document_id created_at]

    # Every document that already exists gets its "created" line so history
    # never starts empty; the source says whether it came in by hand or import.
    execute <<~SQL
      INSERT INTO document_events (document_id, organization_id, action, details, created_at)
      SELECT id, organization_id, 'created',
             json_object('source', source, 'total', CAST(total AS TEXT), 'backfilled', 1),
             created_at
      FROM documents
    SQL
  end

  def down
    drop_table :document_events
  end
end

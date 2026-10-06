class AddBackfillToBankFeeds < ActiveRecord::Migration[8.1]
  def change
    add_column :bank_feeds, :backfill_from,        :date
    add_column :bank_feeds, :backfill_started_at,  :datetime
    add_column :bank_feeds, :backfill_finished_at, :datetime
    add_column :bank_feeds, :backfill_summary,     :text
  end
end

# One bank feed per organisation (SimpleFIN). Claim a setup token, map the
# provider's accounts onto ours, sync on demand, disconnect.
class BankFeedsController < ApplicationController
  before_action :load_feed, only: %i[show update destroy sync]

  def show
    @bank_accounts = Current.organization.bank_accounts.active.ordered.to_a
  end

  # Paste a setup token: claim it for an access URL and pull the account list.
  def create
    access_url = SimpleFin::Client.claim(params.require(:setup_token))
    feed = Current.organization.create_bank_feed!(access_url: access_url)
    SimpleFin::Sync.new(feed).call
    redirect_to bank_feed_path, notice: "Bank feed connected. Map each account below."
  rescue SimpleFin::Error, ActiveRecord::RecordInvalid => e
    redirect_to bank_feed_path, alert: e.message
  end

  # Map provider accounts onto bank accounts; "new" creates one.
  def update
    mappings = params.fetch(:mapping, {}).to_unsafe_h
    @feed.accounts.each do |acct|
      choice = mappings[acct["id"]].to_s
      bank = case choice
      when ""    then nil
      when "new" then Current.organization.bank_accounts.create!(name: acct["name"], kind: BankAccount.guess_kind(acct["name"]), last_four: acct["name"][/(\d{4})\s*\z/, 1])
      else            Current.organization.bank_accounts.find(choice)
      end
      Current.organization.bank_accounts.where(bank_feed: @feed, feed_account_id: acct["id"]).where.not(id: bank&.id).update_all(bank_feed_id: nil, feed_account_id: nil, feed_name: nil)
      bank&.update!(bank_feed: @feed, feed_account_id: acct["id"], feed_name: acct["name"])
    end
    redirect_to bank_feed_path, notice: "Account mapping saved."
  end

  def sync
    unless @feed.sync_allowed?
      return respond_with_status(alert: "Synced #{helpers.time_ago_in_words(@feed.last_synced_at)} ago; try again in a few minutes.")
    end
    summary = SimpleFin::Sync.new(@feed).call
    respond_with_status(notice: "Imported #{summary.imported} (#{summary.duplicates} already there), #{summary.rules_applied} categorized by rules.")
  rescue SimpleFin::Error, SocketError, Timeout::Error => e
    respond_with_status(alert: "Sync failed: #{e.message}")
  end

  def destroy
    @feed.destroy
    redirect_to bank_feed_path, notice: "Bank feed disconnected. Your bank accounts and their transactions are untouched."
  end

  private

  def load_feed
    @feed = Current.organization.bank_feed
    redirect_to bank_feed_path, alert: "No bank feed is connected yet." if @feed.nil? && action_name != "show"
  end

  def respond_with_status(notice: nil, alert: nil)
    @feed.reload
    respond_to do |format|
      format.turbo_stream do
        flash.now[:notice] = notice if notice
        flash.now[:alert]  = alert  if alert
        render "bank_feeds/status"
      end
      format.html { redirect_to bank_feed_path, notice: notice, alert: alert }
    end
  end
end

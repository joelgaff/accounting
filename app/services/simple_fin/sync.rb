module SimpleFin
  # Pull the feed's accounts, drop the lines into the mapped bank accounts,
  # record statement balances, and run the bank rules over what is new.
  class Sync
    OVERLAP_DAYS = 5   # late-posting lines; external ids make the overlap idempotent
    Summary = Struct.new(:accounts, :imported, :duplicates, :rules_applied, :rules_suggested, :unmapped, :errors, keyword_init: true) do
      def to_h = super.merge(unmapped: unmapped.to_a, errors: errors.to_a)
    end

    def initialize(feed, client: feed.client)
      @feed   = feed
      @client = client
      @org    = feed.organization
    end

    def call
      from    = [ (@feed.last_synced_at&.to_date || 90.days.ago.to_date) - OVERLAP_DAYS, (Client::MAX_RANGE_DAYS - 1).days.ago.to_date ].max
      payload = @client.accounts(start_date: from)
      summary = Summary.new(accounts: 0, imported: 0, duplicates: 0, rules_applied: 0, rules_suggested: 0, unmapped: [], errors: payload.errors.dup)

      @feed.update!(accounts: payload.accounts.map { |a| { "id" => a.id, "name" => a.name, "currency" => a.currency, "balance" => a.balance.to_s("F"), "balance_date" => a.balance_date&.iso8601 } })
      by_feed_id = @feed.bank_accounts.index_by(&:feed_account_id)

      payload.accounts.each do |account|
        bank = by_feed_id[account.id]
        unless bank
          summary.unmapped << account.name
          next
        end
        rows = account.transactions.reject(&:pending).map do |t|
          { external_id: t.id, posted_on: t.posted_on, amount: t.amount, payee: t.payee.to_s,
            description: t.description.presence || t.memo.to_s, reference: t.memo }
        end
        result = Imports::BankStatementService.new(rows, bank_account: bank, organization: @org).call
        bank.update!(statement_balance: account.balance, statement_balance_at: account.balance_date, feed_synced_at: Time.current)
        summary.accounts += 1
        summary.imported += result.imported
        summary.duplicates += result.duplicates
        summary.rules_applied += result.rules_applied
        summary.rules_suggested += result.rules_suggested
        summary.errors.concat(result.errors)
      end

      @feed.update!(last_synced_at: Time.current, last_error: nil, last_summary: summary.to_h.to_json)
      summary
    rescue Error, SocketError, Timeout::Error, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError => e
      @feed.update!(last_error: "#{Time.current.utc.iso8601}: #{e.message}")
      raise
    end
  end
end

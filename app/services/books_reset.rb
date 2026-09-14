# Wipes an organisation's books so an import can be run again from scratch.
# Users, the organisation and its Launchpad link are never touched.
#
#   scope: :transactions  — invoices, bills, expenses, payments, journal entries, bank
#                           transactions and every ledger posting. The chart of
#                           accounts, bank accounts, contacts and tax rates stay.
#   scope: :everything    — the above plus the chart, bank accounts, contacts,
#                           tax rates, recurring invoices and Settings.
#
# Runs inside one transaction; dry_run: true rolls it back at the end.
class BooksReset
  SCOPES = %i[transactions everything].freeze

  Report = Struct.new(:scope, :dry_run, :before, :after, keyword_init: true) do
    def to_s
      lines = [ "#{dry_run ? 'DRY RUN — ' : ''}reset scope: #{scope}" ]
      before.each { |table, n| lines << format("  %-22s %6d → %d", table, n, after[table]) }
      lines.join("\n")
    end
  end

  def initialize(organization, scope: :transactions, dry_run: false)
    raise ArgumentError, "scope must be one of #{SCOPES.join(', ')}" unless SCOPES.include?(scope)
    @org     = organization
    @scope   = scope
    @dry_run = dry_run
  end

  def call
    before = counts
    ActiveRecord::Base.transaction do
      wipe_transactions
      wipe_everything if @scope == :everything
      @after = counts
      raise ActiveRecord::Rollback if @dry_run
    end
    Report.new(scope: @scope, dry_run: @dry_run, before: before, after: @after)
  end

  private

  def wipe_transactions
    Payment.where(organization: @org).delete_all
    BankTransaction.where(organization: @org).delete_all
    BankAccount.where(organization: @org).update_all(statement_balance: nil, statement_balance_at: nil, feed_synced_at: nil)
    BankFeed.where(organization: @org).update_all(last_synced_at: nil, last_summary: nil)

    docs    = Document.where(organization: @org)
    doc_ids = docs.pluck(:id)
    purge_attachments("Document", doc_ids)
    line_ids = LineItem.where(lineable_type: "Document", lineable_id: doc_ids).pluck(:id)
    TrackingSelection.where(trackable_type: "LineItem", trackable_id: line_ids).delete_all
    LineItem.where(id: line_ids).delete_all

    # Type rows go before the documents that point at them.
    Invoice.where(id: docs.invoices.select(:documentable_id)).delete_all
    Bill.where(id: docs.bills.select(:documentable_id)).delete_all
    Expense.where(id: docs.expenses.select(:documentable_id)).delete_all
    Deposit.where(id: docs.deposits.select(:documentable_id)).delete_all
    Transfer.where(id: docs.transfers.select(:documentable_id)).delete_all
    journal_ids = docs.journal_entries.pluck(:documentable_id)
    TrackingSelection.where(trackable_type: "JournalLine", trackable_id: JournalLine.where(journal_entry_id: journal_ids).select(:id)).delete_all
    JournalLine.where(journal_entry_id: journal_ids).delete_all
    JournalEntry.where(id: journal_ids).delete_all
    docs.delete_all

    # Every ledger posting hangs off an account owned by this organisation.
    entry_ids = Plutus::Amount.joins(:account).where(plutus_accounts: { tenant_id: @org.id }).distinct.pluck(:entry_id)
    Plutus::Amount.where(entry_id: entry_ids).delete_all
    Plutus::Entry.where(id: entry_ids).delete_all
  end

  def wipe_everything
    recurring_ids = @org.recurring_invoices.pluck(:id)
    recurring_line_ids = LineItem.where(lineable_type: "RecurringInvoice", lineable_id: recurring_ids).pluck(:id)
    TrackingSelection.where(trackable_type: "LineItem", trackable_id: recurring_line_ids).delete_all
    LineItem.where(id: recurring_line_ids).delete_all
    RecurringInvoice.where(organization: @org).delete_all

    OrganizationSettings.where(organization: @org).delete_all
    TrackingSelection.where(trackable_type: "BankRule", trackable_id: BankRule.where(organization: @org).select(:id)).delete_all
    BankRule.where(organization: @org).delete_all
    TrackingSelection.where(tracking_category_id: TrackingCategory.where(organization: @org).select(:id)).delete_all
    TrackingOption.where(tracking_category_id: TrackingCategory.where(organization: @org).select(:id)).delete_all
    TrackingCategory.where(organization: @org).delete_all
    BankAccount.where(organization: @org).update_all(bank_feed_id: nil, feed_account_id: nil, feed_name: nil, feed_synced_at: nil)
    BankFeed.where(organization: @org).delete_all
    TaxRate.where(organization: @org).delete_all
    BankAccount.where(organization: @org).delete_all
    Plutus::Account.where(tenant_id: @org.id).delete_all
    Contact.where(organization: @org).delete_all
  end

  def purge_attachments(record_type, ids)
    return if ids.empty?
    ActiveStorage::Attachment.where(record_type: record_type, record_id: ids).find_each do |attachment|
      @dry_run ? attachment.destroy : attachment.purge
    end
  end

  def counts
    {
      "invoices"           => @org.documents.invoices.count,
      "bills"              => @org.documents.bills.count,
      "expenses"           => @org.documents.expenses.count,
      "deposits"           => @org.documents.deposits.count,
      "transfers"          => @org.documents.transfers.count,
      "payments"           => Payment.where(organization: @org).count,
      "journal_entries"    => @org.documents.journal_entries.count,
      "bank_transactions"  => @org.bank_transactions.count,
      "bank_rules"         => @org.bank_rules.count,
      "tracking_categories" => @org.tracking_categories.count,
      "ledger_entries"     => Plutus::Amount.joins(:account).where(plutus_accounts: { tenant_id: @org.id }).distinct.count(:entry_id),
      "accounts"           => @org.plutus_accounts.count,
      "bank_accounts"      => @org.bank_accounts.count,
      "contacts"           => @org.contacts.count,
      "tax_rates"          => @org.tax_rates.count,
      "recurring_invoices" => @org.recurring_invoices.count
    }
  end
end

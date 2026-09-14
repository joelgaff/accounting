# Xero migration toolkit. Every task picks the organisation the same way:
# ORG_ID=n, otherwise the single organisation. DRY_RUN=1 rolls the work back.
#
#   bin/rails 'xero:import[/path/to/bundle]'   run a bundle of Xero CSVs
#   bin/rails xero:status                      what the books hold right now
#   bin/rails xero:reset                       wipe transactions, keep the chart
#   bin/rails 'xero:reset[everything]'         wipe the lot, back to an empty org
#
# In production, reset refuses to run unless CONFIRM=<organisation name>.
namespace :xero do
  def xero_org
    org = ENV["ORG_ID"].present? ? Organization.find(ENV["ORG_ID"]) : Organization.sole
    Current.organization = org
    org
  end

  desc "Import a bundle of Xero-format CSVs into the books (see Imports::BundleService). DRY_RUN=1 rolls back; ORG_ID picks the organisation."
  task :import, [ :dir ] => :environment do |_, args|
    dir = args[:dir].presence or abort "usage: bin/rails 'xero:import[/path/to/bundle]'   (DRY_RUN=1 to roll back, ORG_ID=n to pick an org)"

    org = xero_org
    report = Imports::BundleService.new(dir, organization: org, dry_run: ENV["DRY_RUN"].present?).call
    puts "Importing #{dir} into #{org.name} (#{Rails.env})"
    puts report
    abort "import finished with errors" if report.failed?
  end

  desc "Show what the books hold: counts, date ranges, trial balance, settings"
  task status: :environment do
    org = xero_org
    s   = org.settings
    debits  = Plutus::DebitAmount.joins(:account).where(plutus_accounts: { tenant_id: org.id }).sum(:amount)
    credits = Plutus::CreditAmount.joins(:account).where(plutus_accounts: { tenant_id: org.id }).sum(:amount)

    range = ->(scope, col) { scope.any? ? "#{scope.minimum(col)} .. #{scope.maximum(col)}" : "—" }
    rows = [
      [ "organisation",      "#{org.name} (id #{org.id}, #{Rails.env})" ],
      [ "accounts",          org.plutus_accounts.count ],
      [ "bank accounts",     org.bank_accounts.map { |b| "#{b.name} [#{b.kind}]" }.join(", ").presence || "—" ],
      [ "contacts",          org.contacts.count ],
      [ "tax rates",         org.tax_rates.count ],
      [ "invoices",          "#{org.documents.invoices.count}  #{range.(org.documents.invoices, :date)}" ],
      [ "bills",             "#{org.documents.bills.count}  #{range.(org.documents.bills, :date)}" ],
      [ "expenses",          "#{org.documents.expenses.count}  #{range.(org.documents.expenses, :date)}" ],
      [ "deposits",          "#{org.documents.deposits.count}  #{range.(org.documents.deposits, :date)}" ],
      [ "transfers",         "#{org.documents.transfers.count}  #{range.(org.documents.transfers, :date)}" ],
      [ "payments",          Payment.where(organization: org).count ],
      [ "journal entries",   "#{org.documents.journal_entries.count}  #{range.(org.documents.journal_entries, :date)}" ],
      [ "bank transactions", org.bank_transactions.count ],
      [ "trial balance",     format("debits %.2f  credits %.2f  %s", debits, credits, debits == credits ? "BALANCED" : "OUT OF BALANCE") ],
      [ "settings",          "AR=#{s.receivable_account&.name || '—'}  AP=#{s.payable_account&.name || '—'}  bank=#{s.bank_account&.name || '—'}" ]
    ]
    rows.each { |k, v| puts format("  %-18s %s", k, v) }
  end

  desc "Wipe the books to re-run an import. Default keeps the chart, bank accounts, contacts and tax rates; 'everything' removes those too. DRY_RUN=1 previews; production needs CONFIRM=<org name>."
  task :reset, [ :scope ] => :environment do |_, args|
    org   = xero_org
    scope = (args[:scope].presence || "transactions").to_sym
    abort "scope must be 'transactions' or 'everything'" unless BooksReset::SCOPES.include?(scope)

    dry_run = ENV["DRY_RUN"].present?
    if Rails.env.production? && !dry_run && ENV["CONFIRM"] != org.name
      abort "Refusing to reset production books for #{org.name.inspect}. Re-run with CONFIRM=#{org.name.inspect} (or DRY_RUN=1 to preview)."
    end

    puts BooksReset.new(org, scope: scope, dry_run: dry_run).call
  end
end

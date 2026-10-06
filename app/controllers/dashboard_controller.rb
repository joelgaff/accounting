class DashboardController < ApplicationController
  # label, the Settings slot it reads, and where the card takes you.
  KPI_SLOTS = [
    [ "Operating Bank",       :bank_account,       ->(h, account) { h.bank_account_path(account) } ],
    [ "Accounts Receivable",  :receivable_account, ->(h, _) { h.reports_accounts_receivable_aging_path } ],
    [ "Accounts Payable",     :payable_account,    ->(h, _) { h.reports_accounts_payable_aging_path } ]
  ].freeze

  def index
    settings = Current.organization.settings

    @kpis = KPI_SLOTS.map do |label, attr, path|
      account = settings.public_send(attr)
      [ label, account, account&.balance || BigDecimal("0"), (path.call(helpers, account) if account) ]
    end

    @missing_slots = KPI_SLOTS.select { |_, attr| settings.public_send(attr).nil? }.map(&:first)

    @recent_entries = Plutus::Entry
                        .joins(debit_amounts: :account)
                        .where(plutus_accounts: { tenant_id: Current.organization.id })
                        .distinct
                        .order(date: :desc, id: :desc)
                        .limit(10)
                        .preload(:commercial_document)
    @entry_totals = Plutus::DebitAmount.where(entry_id: @recent_entries.map(&:id)).group(:entry_id).sum(:amount)
    documents = @recent_entries.map(&:commercial_document).compact
    ActiveRecord::Associations::Preloader.new(records: documents.grep(Payment), associations: { document: :documentable }).call
    ActiveRecord::Associations::Preloader.new(records: documents.grep(Document), associations: :documentable).call
  end
end

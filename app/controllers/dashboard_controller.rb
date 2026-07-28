class DashboardController < ApplicationController
  before_action :require_login

  KPI_ACCOUNT_NAMES = ["Operating Bank", "Accounts Receivable", "Accounts Payable"].freeze

  def index
    @kpis = KPI_ACCOUNT_NAMES.index_with { |name| Ledger.balance(name) }
    @missing_accounts = KPI_ACCOUNT_NAMES.reject { |name| Ledger.lookup(name) }
    @recent_entries = Plutus::Entry
                        .joins(:accounts)
                        .where(plutus_accounts: { tenant_id: Current.organization.id })
                        .distinct
                        .order(created_at: :desc)
                        .limit(10)
  end
end

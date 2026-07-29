class DashboardController < ApplicationController
  before_action :require_login

  KPI_SLOTS = [
    ["Operating Bank",       :bank_account],
    ["Accounts Receivable",  :receivable_account],
    ["Accounts Payable",     :payable_account]
  ].freeze

  def index
    settings = Current.organization.settings

    @kpis = KPI_SLOTS.map do |label, attr|
      account = settings.public_send(attr)
      [label, account, account&.balance || BigDecimal("0")]
    end

    @missing_slots = KPI_SLOTS.select { |_, attr| settings.public_send(attr).nil? }.map(&:first)

    @recent_entries = Plutus::Entry
                        .joins(debit_amounts: :account)
                        .where(plutus_accounts: { tenant_id: Current.organization.id })
                        .distinct
                        .order(created_at: :desc)
                        .limit(10)
  end
end

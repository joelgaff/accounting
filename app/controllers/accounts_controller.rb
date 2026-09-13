class AccountsController < ApplicationController
  TYPE_ORDER = %w[Plutus::Asset Plutus::Liability Plutus::Equity Plutus::Revenue Plutus::Expense].freeze

  def index
    accounts = Plutus::Account.where(tenant: Current.organization).includes(:bank_account).order(:code, :name).to_a
    @grouped = accounts.group_by(&:type).sort_by { |type, _| TYPE_ORDER.index(type) || 999 }
  end
end

class ReportsController < ApplicationController
  before_action :require_login

  def index
  end

  def profit_and_loss
    @from, @to = parse_range(default_from: Date.current.beginning_of_year)
    @report = Reports::ProfitAndLoss.new(organization: Current.organization, from: @from, to: @to)
  end

  def balance_sheet
    @as_of = parse_date(:as_of, default: Date.current)
    @report = Reports::BalanceSheet.new(organization: Current.organization, as_of: @as_of)
  end

  def trial_balance
    @from, @to = parse_range(default_from: Date.current.beginning_of_year)
    @report = Reports::TrialBalance.new(organization: Current.organization, from: @from, to: @to)
  end

  def general_ledger
    @from, @to = parse_range(default_from: Date.current.beginning_of_year)
    @accounts  = Plutus::Account.where(tenant: Current.organization).order(:type, :code, :name)
    @account   = @accounts.find_by(id: params[:account_id]) || @accounts.first
    return unless @account
    @report = Reports::GeneralLedger.new(organization: Current.organization, account: @account, from: @from, to: @to)
  end

  private

  def parse_range(default_from:)
    from = parse_date(:from, default: default_from)
    to   = parse_date(:to,   default: Date.current)
    [from, to]
  end

  def parse_date(key, default:)
    return default if params[key].blank?
    Date.parse(params[key])
  rescue ArgumentError
    default
  end
end

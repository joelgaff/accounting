class Reports::GeneralLedgersController < Reports::BaseController
  def show
    @from, @to = parse_range(default_from: Date.current.beginning_of_year)
    @accounts  = Plutus::Account.where(tenant: Current.organization).order(:type, :code, :name)
    @account   = @accounts.find_by(id: params[:account_id]) || @accounts.first
    return unless @account
    @report = Reports::GeneralLedger.new(organization: Current.organization, account: @account, from: @from, to: @to)
  end
end

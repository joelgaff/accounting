class Reports::ProfitAndLossesController < Reports::BaseController
  def show
    @from, @to = parse_range(default_from: Date.current.beginning_of_year)
    @report = Reports::ProfitAndLoss.new(organization: Current.organization, from: @from, to: @to)
  end
end

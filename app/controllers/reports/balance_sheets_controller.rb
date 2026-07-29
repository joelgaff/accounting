class Reports::BalanceSheetsController < Reports::BaseController
  def show
    @as_of = parse_date(:as_of, default: Date.current)
    @report = Reports::BalanceSheet.new(organization: Current.organization, as_of: @as_of)
  end
end

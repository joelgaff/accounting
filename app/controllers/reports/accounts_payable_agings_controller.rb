class Reports::AccountsPayableAgingsController < Reports::BaseController
  def show
    @as_of  = parse_date(:as_of, default: Date.current)
    @report = Reports::AccountsPayableAging.new(organization: Current.organization, as_of: @as_of)
  end
end

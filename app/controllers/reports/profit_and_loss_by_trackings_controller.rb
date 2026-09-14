class Reports::ProfitAndLossByTrackingsController < Reports::BaseController
  def show
    @from, @to  = parse_range(default_from: Date.current.beginning_of_year)
    @categories = Current.organization.tracking_categories.ordered.includes(:options).to_a
    @category   = @categories.find { |c| c.id.to_s == params[:tracking_category_id].to_s } || @categories.first
    @report     = Reports::ProfitAndLossByTracking.new(organization: Current.organization, category: @category, from: @from, to: @to) if @category
  end
end

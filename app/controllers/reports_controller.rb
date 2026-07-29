# Landing page listing every report. Individual reports live under
# Reports::* (see app/controllers/reports/), one controller per report.
class ReportsController < ApplicationController
  before_action :require_login

  def index; end
end

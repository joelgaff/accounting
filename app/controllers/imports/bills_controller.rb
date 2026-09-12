class Imports::BillsController < ApplicationController
  include CsvUpload

  def new
  end

  def create
    return unless require_uploaded_file
    result = Imports::XeroBillsService.new(params[:file].read, organization: Current.organization).call
    redirect_to expenses_path, notice: summarize_result(result)
  end
end

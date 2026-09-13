class Imports::TaxRatesController < ApplicationController
  include CsvUpload

  def new
  end

  def create
    return unless require_uploaded_file
    result = Imports::TaxRatesService.new(params[:file].read, organization: Current.organization).call
    redirect_to tax_rates_path, notice: summarize_result(result)
  end
end

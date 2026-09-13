class Imports::JournalsController < ApplicationController
  include CsvUpload

  def new
  end

  def create
    return unless require_uploaded_file
    documents = params[:documents] == "include" ? :include : :skip
    result = Imports::XeroJournalsService.new(params[:file].read, organization: Current.organization, documents: documents).call
    redirect_to journal_entries_path, notice: summarize_result(result)
  end
end

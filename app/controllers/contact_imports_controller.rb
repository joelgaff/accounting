class ContactImportsController < ApplicationController
  include CsvUpload
  before_action :require_login

  def new; end

  def create
    return unless require_uploaded_file
    kind = params[:default_kind].presence_in(Contact::KINDS) || "both"
    result = ContactsImportService.new(params[:file].read, organization: Current.organization, default_kind: kind).call
    redirect_to contacts_path, notice: summarize_result(result)
  end
end

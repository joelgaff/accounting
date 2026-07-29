class ContactImportsController < ApplicationController
  before_action :require_login

  def new; end

  def create
    file = params[:file]
    if file.blank?
      flash.now[:alert] = "Choose a CSV file."
      return render :new, status: :unprocessable_entity
    end

    kind = params[:default_kind].presence_in(Contact::KINDS) || "both"
    result = ContactsImportService.new(file.read, organization: Current.organization, default_kind: kind).call

    msg = "Created #{result.created}, updated #{result.updated}, skipped #{result.skipped}."
    msg += " Errors: #{result.errors.first(5).join("; ")}" if result.errors.any?
    msg += " (+ #{result.errors.size - 5} more)" if result.errors.size > 5
    redirect_to contacts_path, notice: msg
  end
end

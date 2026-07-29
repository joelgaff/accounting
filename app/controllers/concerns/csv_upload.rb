module CsvUpload
  extend ActiveSupport::Concern

  private

  def require_uploaded_file
    if params[:file].blank?
      flash.now[:alert] = "Choose a CSV file."
      render :new, status: :unprocessable_entity
      false
    else
      true
    end
  end

  # Turn an Imports::BaseService::Result into a flash-friendly string.
  def summarize_result(result)
    parts = []
    parts << "Created #{result.created}"     if result.created.positive?
    parts << "updated #{result.updated}"     if result.updated.positive?
    parts << "skipped #{result.skipped}"     if result.skipped.positive?
    parts << "duplicates #{result.duplicates}" if result.duplicates.positive?
    msg = parts.join(", ").sub(/\A(\w)/) { $1.upcase } + "."
    if result.errors.any?
      first = result.errors.first(5).join("; ")
      more  = result.errors.size > 5 ? " (+ #{result.errors.size - 5} more)" : ""
      msg += " Errors: #{first}#{more}"
    end
    msg
  end
end

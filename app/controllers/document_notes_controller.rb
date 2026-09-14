# A note on a document's history, the way Xero's History & Notes takes them.
class DocumentNotesController < ApplicationController
  def create
    @document = Current.organization.documents.find(params[:document_id])
    text      = params.require(:note)[:text].to_s.strip
    if text.blank?
      redirect_to helpers.document_path_for(@document), alert: "A note needs some text."
      return
    end
    @event = @document.record_event!(:note, text: text.truncate(2000))
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to helpers.document_path_for(@document), notice: "Note added." }
    end
  end
end

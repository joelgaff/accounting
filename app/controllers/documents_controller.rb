# Shared actions for every document type. A subclass names its type, permits
# its type-specific attributes, and loads its form collections.
class DocumentsController < ApplicationController
  include Paginatable

  before_action :load_form_collections, only: %i[new create edit update]
  before_action :load_document,         if: -> { params[:id].present? }   # every member action, subclasses included
  before_action :refuse_if_voided,      only: %i[edit update void]

  def index
    @status    = params[:status].presence
    @documents = paginate(filtered.includes(:documentable, :contact, :payments).chronological)
  end

  def show; end

  def new
    @document = build_document
  end

  def create
    @document = build_document
    @document.assign_attributes(document_params)
    if @document.save
      redirect_to after_create_path, notice: created_notice
    else
      after_failed_create
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    @document.update_and_repost!(document_params)
    redirect_to helpers.document_path_for(@document), notice: "#{type_name} updated."
  rescue ActiveRecord::RecordInvalid
    after_failed_update
    render :edit, status: :unprocessable_entity
  end

  def void
    @document.void!
    respond_to do |format|
      format.turbo_stream { render "documents/void" }
      format.html { redirect_to helpers.document_path_for(@document), notice: "#{type_name} voided." }
    end
  end

  private

  def documentable_class     = raise(NotImplementedError)
  def documentable_permitted = raise(NotImplementedError)
  def load_form_collections; end
  def after_failed_create; end
  def after_failed_update; end
  def after_create_path      = helpers.document_path_for(@document)
  def created_notice         = "#{type_name} created."
  def type_name              = documentable_class.model_name.human
  def universal_permitted    = %i[contact_id date reference memo]

  def scope
    Current.organization.documents.public_send(documentable_class.model_name.plural)
  end

  # ?status= narrows the index: voided, all, or one of the type's own statuses.
  def filtered
    case @status
    when "voided" then scope.voided
    when "all"    then scope
    when nil, ""  then scope.live
    else               scope.live.includes(:payments, :documentable).select { |d| d.status == @status }
    end
  end

  def load_document
    @document = scope.find(params[:id])
  end

  def refuse_if_voided
    return unless @document.voided?
    redirect_to helpers.document_path_for(@document), alert: "#{@document.label} is voided and can't be changed."
  end

  def build_document
    Current.organization.documents.build(date: Date.current, documentable: documentable_class.new)
  end

  def document_params
    params.require(:document).permit(
      *universal_permitted,
      attachments: [],
      line_items_attributes: %i[id description quantity unit_amount account_id tax_rate_id _destroy],
      documentable_attributes: documentable_permitted
    )
  end
end

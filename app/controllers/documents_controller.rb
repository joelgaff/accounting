# Shared index/show/new/create for every document type. A subclass names its
# type, permits its type-specific attributes, and loads its form collections.
class DocumentsController < ApplicationController
  before_action :load_form_collections, only: %i[new create]

  def index
    @documents = scope.includes(:documentable, :contact, :payments).chronological
  end

  def show
    @document = scope.find(params[:id])
  end

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

  private

  def documentable_class     = raise(NotImplementedError)
  def documentable_permitted = raise(NotImplementedError)
  def load_form_collections; end
  def after_failed_create; end
  def after_create_path      = helpers.document_path_for(@document)
  def created_notice         = "#{documentable_class.model_name.human} created."

  def scope
    Current.organization.documents.public_send(documentable_class.model_name.plural)
  end

  def build_document
    Current.organization.documents.build(date: Date.current, documentable: documentable_class.new)
  end

  def document_params
    params.require(:document).permit(
      :contact_id, :date, :reference, :memo,
      attachments: [],
      line_items_attributes: %i[id description quantity unit_amount account_id tax_rate_id _destroy],
      documentable_attributes: documentable_permitted
    )
  end
end

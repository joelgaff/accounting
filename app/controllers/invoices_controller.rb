class InvoicesController < DocumentsController
  before_action :load_document, only: %i[print email send_email]

  def print; end
  def email; end

  def send_email
    to      = params.require(:to)
    subject = params[:subject].presence
    body    = params[:body].presence

    InvoiceMailer.send_invoice(@document, to: to, subject: subject, body: body).deliver_later
    redirect_to invoice_path(@document), notice: "Invoice emailed to #{to}."
  end

  private

  def documentable_class     = Invoice
  def documentable_permitted = %i[client_name due_date receivable_account_id]
  def after_create_path      = invoices_path

  def build_document
    super.tap { |doc| doc.invoice.due_date = Date.current + 30.days }
  end

  def load_document
    @document = scope.find(params[:id])
  end

  def load_form_collections
    @receivable_accounts = Plutus::Asset.where(tenant: Current.organization).order(:name)
    @revenue_accounts    = Plutus::Revenue.where(tenant: Current.organization).order(:name)
    @customers           = Current.organization.contacts.customers.ordered
    @tax_rates           = Current.organization.tax_rates.ordered
  end
end

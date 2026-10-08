class InvoicesController < DocumentsController
  before_action :refuse_if_draft, only: %i[email send_email]
  before_action -> { require_control_account(:receivable_account, "Accounts Receivable") }, only: %i[new create]

  def print
    respond_to do |format|
      format.html
      format.pdf { send_data InvoicePdf.new(@document).render, filename: InvoicePdf.filename(@document), type: "application/pdf", disposition: "inline" }
    end
  end
  def email; end

  def send_email
    to      = params.require(:to)
    subject = params[:subject].presence
    body    = params[:body].presence

    InvoiceMailer.send_invoice(@document, to: to, subject: subject, body: body).deliver_later
    @document.record_event!(:emailed, to: to, subject: subject || InvoiceMailer.default_subject(@document), pdf: true)
    redirect_to invoice_path(@document), notice: "Invoice emailed to #{to} with the PDF attached."
  end

  private

  def refuse_if_draft
    return unless @document.draft?
    redirect_to invoice_path(@document), alert: "#{@document.label} is a draft; approve it before emailing."
  end

  def documentable_class     = Invoice
  def documentable_permitted = %i[number client_name due_date]
  def after_create_path      = invoices_path

  def build_document
    super.tap do |doc|
      doc.invoice.due_date           = Date.current + 30.days
      doc.invoice.number             = Invoice.next_number(Current.organization)
      doc.invoice.receivable_account = Current.organization.settings.receivable_account
    end
  end

  def load_form_collections
    @revenue_accounts    = Plutus::Revenue.where(tenant: Current.organization).order(:name)
    @customers           = Current.organization.contacts.customers.ordered
    @tax_rates           = Current.organization.tax_rates.ordered
  end
end

class InvoicesController < ApplicationController
  before_action :require_login
  before_action :load_accounts, only: %i[new create]

  def index
    @invoices = Current.organization.invoices.order(created_at: :desc)
  end

  def show
    @invoice = Current.organization.invoices.find(params[:id])
  end

  def print
    @invoice = Current.organization.invoices.find(params[:id])
  end

  def email
    @invoice = Current.organization.invoices.find(params[:id])
  end

  def send_email
    invoice = Current.organization.invoices.find(params[:id])
    to      = params.require(:to)
    subject = params[:subject].presence
    body    = params[:body].presence

    InvoiceMailer.send_invoice(invoice, to: to, subject: subject, body: body).deliver_later
    redirect_to invoice_path(invoice), notice: "Invoice emailed to #{to}."
  end

  def new
    @invoice = Current.organization.invoices.build(due_date: Date.current + 30.days)
  end

  def create
    @invoice = Current.organization.invoices.build(invoice_params)
    if @invoice.save
      redirect_to invoices_path, notice: "Invoice created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def load_accounts
    @receivable_accounts = Plutus::Asset.where(tenant: Current.organization).order(:name)
    @revenue_accounts    = Plutus::Revenue.where(tenant: Current.organization).order(:name)
    @customers           = Current.organization.contacts.customers.ordered
    @tax_rates           = Current.organization.tax_rates.ordered
  end

  def invoice_params
    params.require(:invoice).permit(
      :contact_id, :client_name, :amount, :due_date,
      :receivable_account_id, :revenue_account_id, :tax_rate_id,
      attachments: [],
      line_items_attributes: %i[id description quantity unit_amount account_id tax_rate_id _destroy]
    )
  end
end

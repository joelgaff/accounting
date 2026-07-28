class InvoicesController < ApplicationController
  before_action :require_login
  before_action :load_accounts, only: %i[new create]

  def index
    @invoices = Current.organization.invoices.order(created_at: :desc)
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
  end

  def invoice_params
    params.require(:invoice).permit(:client_name, :amount, :due_date, :receivable_account_id, :revenue_account_id)
  end
end

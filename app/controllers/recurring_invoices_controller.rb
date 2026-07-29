class RecurringInvoicesController < ApplicationController
  before_action :require_login
  before_action :load_form_collections, only: %i[new create edit update]
  before_action :load_recurring, only: %i[show edit update destroy run_now]

  def index
    @recurring_invoices = Current.organization.recurring_invoices.order(next_run_on: :asc)
  end

  def show; end

  def new
    @recurring_invoice = Current.organization.recurring_invoices.build(
      frequency: "monthly", interval: 1, net_days: 30, next_run_on: Date.current + 1.day
    )
    @recurring_invoice.line_items.build
  end

  def create
    @recurring_invoice = Current.organization.recurring_invoices.build(recurring_params)
    if @recurring_invoice.save
      redirect_to recurring_invoice_path(@recurring_invoice), notice: "Recurring invoice created."
    else
      @recurring_invoice.line_items.build if @recurring_invoice.line_items.empty?
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @recurring_invoice.update(recurring_params)
      redirect_to recurring_invoice_path(@recurring_invoice), notice: "Recurring invoice updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @recurring_invoice.destroy
    redirect_to recurring_invoices_path, notice: "Recurring invoice removed."
  end

  # Generates one Invoice immediately, advances next_run_on.
  def run_now
    invoice = @recurring_invoice.generate!
    respond_to do |format|
      format.turbo_stream {
        render turbo_stream: [
          turbo_stream.prepend("generated-invoices",
            render_to_string(partial: "generated_invoice", locals: { invoice: invoice })),
          turbo_stream.replace(dom_id(@recurring_invoice, :schedule),
            render_to_string(partial: "schedule", locals: { recurring_invoice: @recurring_invoice }))
        ]
      }
      format.html { redirect_to recurring_invoice_path(@recurring_invoice), notice: "Generated Invoice ##{invoice.id}." }
    end
  end

  private

  def load_recurring
    @recurring_invoice = Current.organization.recurring_invoices.find(params[:id])
  end

  def load_form_collections
    @receivable_accounts = Plutus::Asset.where(tenant: Current.organization).order(:code, :name)
    @revenue_accounts    = Plutus::Revenue.where(tenant: Current.organization).order(:code, :name)
    @customers           = Current.organization.contacts.customers.ordered
    @tax_rates           = Current.organization.tax_rates.ordered
  end

  def recurring_params
    params.require(:recurring_invoice).permit(
      :contact_id, :client_name, :receivable_account_id, :net_days,
      :frequency, :interval, :next_run_on, :end_on, :active, :email_on_generate,
      line_items_attributes: %i[id description quantity unit_amount account_id tax_rate_id _destroy]
    )
  end
end

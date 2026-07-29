class PaymentsController < ApplicationController
  before_action :require_login
  before_action :load_payable

  def new
    @payment = @payable.payments.build(
      organization: Current.organization,
      amount: @payable.balance_due,
      paid_on: Date.current,
      bank_account: Current.organization.settings.bank_account
    )
    load_bank_options
  end

  def create
    @payment = @payable.payments.build(payment_params.merge(organization: Current.organization))
    if @payment.save
      redirect_to redirect_target, notice: "Payment recorded."
    else
      load_bank_options
      render :new, status: :unprocessable_entity
    end
  end

  private

  def load_payable
    if params[:invoice_id]
      @payable = Current.organization.invoices.find(params[:invoice_id])
    else
      @payable = Current.organization.expenses.find(params[:expense_id])
    end
  end

  def load_bank_options
    @bank_accounts = Plutus::Asset.where(tenant: Current.organization).order(:code, :name)
  end

  def redirect_target
    @payable.is_a?(Invoice) ? invoice_path(@payable) : expense_path(@payable)
  end

  def payment_params
    params.require(:payment).permit(:amount, :paid_on, :bank_account_id, :reference, :memo)
  end
end

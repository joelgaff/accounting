class PaymentsController < ApplicationController
  before_action :load_document

  def new
    @payment = @document.payments.build(
      organization: Current.organization,
      amount: @document.balance_due,
      paid_on: Date.current,
      bank_account: Current.organization.settings.bank_account
    )
    load_bank_options
  end

  def create
    @payment = @document.payments.build(payment_params.merge(organization: Current.organization))
    if @payment.save
      redirect_to helpers.document_path_for(@document), notice: "Payment recorded."
    else
      load_bank_options
      render :new, status: :unprocessable_entity
    end
  end

  private

  def load_document
    @document = Current.organization.documents.find(params[:document_id])
  end

  def load_bank_options
    @bank_accounts = Current.organization.bank_accounts.active.ordered
  end

  def payment_params
    params.require(:payment).permit(:amount, :paid_on, :bank_account_id, :reference, :memo)
  end
end

class ExpensesController < ApplicationController
  before_action :require_login
  before_action :load_accounts, only: %i[new create]

  def index
    @expenses = Current.organization.expenses.order(incurred_on: :desc, created_at: :desc)
  end

  def show
    @expense = Current.organization.expenses.find(params[:id])
  end

  def new
    @expense = Current.organization.expenses.build(incurred_on: Date.current)
  end

  def create
    @expense = Current.organization.expenses.build(expense_params)
    if @expense.save
      redirect_to expenses_path, notice: "Expense recorded."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def load_accounts
    scope = Plutus::Account.where(tenant: Current.organization)
    @expense_accounts   = scope.where(type: "Plutus::Expense").order(:name)
    @paid_from_accounts = scope.where(type: %w[Plutus::Asset Plutus::Liability]).order(:type, :name)
    @vendors            = Current.organization.contacts.vendors.ordered
    @tax_rates          = Current.organization.tax_rates.ordered
  end

  def expense_params
    params.require(:expense).permit(:contact_id, :vendor, :amount, :incurred_on, :memo,
                                    :expense_account_id, :paid_from_account_id, :tax_rate_id,
                                    receipts: [])
  end
end

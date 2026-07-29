class TaxRatesController < ApplicationController
  before_action :require_login
  before_action :load_accounts, only: %i[new create edit update]

  def index
    @tax_rates = Current.organization.tax_rates.ordered
  end

  def new
    @tax_rate = Current.organization.tax_rates.build
  end

  def create
    @tax_rate = Current.organization.tax_rates.build(tax_rate_params)
    if @tax_rate.save
      redirect_to tax_rates_path, notice: "Tax rate added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @tax_rate = Current.organization.tax_rates.find(params[:id])
  end

  def update
    @tax_rate = Current.organization.tax_rates.find(params[:id])
    if @tax_rate.update(tax_rate_params)
      redirect_to tax_rates_path, notice: "Tax rate updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    tax_rate = Current.organization.tax_rates.find(params[:id])
    tax_rate.destroy
    redirect_to tax_rates_path, notice: "Tax rate removed."
  end

  private

  def load_accounts
    scope = Plutus::Account.where(tenant: Current.organization).order(:code, :name)
    @liability_accounts = scope.where(type: "Plutus::Liability")
    @asset_accounts     = scope.where(type: "Plutus::Asset")
  end

  def tax_rate_params
    params.require(:tax_rate).permit(:name, :rate, :xero_tax_type, :liability_account_id, :asset_account_id)
  end
end

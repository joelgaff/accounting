class SettingsController < ApplicationController
  before_action :require_login

  def show
    @settings        = Current.organization.settings
    @asset_accounts     = Plutus::Asset.where(tenant: Current.organization).order(:code, :name)
    @liability_accounts = Plutus::Liability.where(tenant: Current.organization).order(:code, :name)
  end

  def update
    @settings = Current.organization.settings
    if @settings.update(settings_params)
      redirect_to settings_path, notice: "Settings updated."
    else
      @asset_accounts     = Plutus::Asset.where(tenant: Current.organization).order(:code, :name)
      @liability_accounts = Plutus::Liability.where(tenant: Current.organization).order(:code, :name)
      render :show, status: :unprocessable_entity
    end
  end

  private

  def settings_params
    params.require(:organization_settings).permit(:bank_account_id, :receivable_account_id, :payable_account_id)
  end
end

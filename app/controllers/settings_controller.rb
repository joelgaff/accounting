class SettingsController < ApplicationController
  def show
    @settings        = Current.organization.settings
    load_accounts
  end

  def update
    @settings = Current.organization.settings
    if @settings.update(settings_params)
      redirect_to settings_path, notice: "Settings updated."
    else
      load_accounts
      render :show, status: :unprocessable_entity
    end
  end

  private

  def load_accounts
    @bank_accounts      = Current.organization.bank_accounts.active.ordered
    @asset_accounts     = Plutus::Asset.where(tenant: Current.organization).order(:code, :name)
    @liability_accounts = Plutus::Liability.where(tenant: Current.organization).order(:code, :name)
  end

  def settings_params
    params.require(:organization_settings).permit(:bank_account_id, :receivable_account_id, :payable_account_id)
  end
end

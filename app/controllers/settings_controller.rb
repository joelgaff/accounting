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

  # Per-person, not per-organisation: the theme is saved on the user record
  # and follows them to any device. The page paints it before this returns.
  def appearance
    if Current.user.update(theme: params.require(:user)[:theme])
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to settings_path, notice: "Switched to the #{Current.user.theme} theme." }
      end
    else
      Current.user.reload
      redirect_to settings_path, alert: "That isn't one of the themes."
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

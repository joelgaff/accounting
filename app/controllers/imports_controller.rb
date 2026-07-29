class ImportsController < ApplicationController
  before_action :require_login
  before_action :load_accounts

  def new
  end

  def create
    file = params[:file]
    bank_account   = @asset_accounts.find { |a| a.id.to_s == params[:bank_account_id].to_s }
    paired_account = @all_accounts.find   { |a| a.id.to_s == params[:paired_account_id].to_s }

    if file.blank? || bank_account.nil? || paired_account.nil?
      flash.now[:alert] = "Choose a CSV file, a bank account, and a paired account."
      return render :new, status: :unprocessable_entity
    end

    result = BankImportService.new(file.read, bank_account: bank_account, paired_account: paired_account).call

    msg = "Imported #{result.imported}, skipped #{result.skipped}."
    msg += " Errors: #{result.errors.join("; ")}" if result.errors.any?
    redirect_to root_path, notice: msg
  end

  private

  def load_accounts
    scope = Plutus::Account.where(tenant: Current.organization).order(:type, :name)
    @asset_accounts = scope.where(type: "Plutus::Asset")
    @all_accounts   = scope
  end
end

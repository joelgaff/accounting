class Imports::BankController < ApplicationController
  before_action :require_login
  before_action :load_accounts

  def new
  end

  def create
    file         = params[:file]
    bank_account = @asset_accounts.find { |a| a.id.to_s == params[:bank_account_id].to_s }

    if file.blank? || bank_account.nil?
      flash.now[:alert] = "Choose a CSV file and a bank account."
      return render :new, status: :unprocessable_entity
    end

    result = Imports::BankStatementService.new(
      file.read, bank_account: bank_account, organization: Current.organization
    ).call

    msg = "Imported #{result.imported}, duplicates skipped #{result.duplicates}."
    msg += " Errors: #{result.errors.first(5).join('; ')}" if result.errors.any?
    redirect_to bank_transactions_path, notice: msg
  end

  private

  def load_accounts
    @asset_accounts = Plutus::Asset.where(tenant: Current.organization).order(:code, :name)
  end
end

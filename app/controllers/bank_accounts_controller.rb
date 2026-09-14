class BankAccountsController < ApplicationController
  before_action :load_bank_account, only: %i[show edit update archive restore]

  def index
    @active   = Current.organization.bank_accounts.active.ordered.includes(:account)
    @archived = Current.organization.bank_accounts.archived.ordered.includes(:account)
  end

  # Account transactions: every movement on the bank's ledger account.
  def show
    @from = parse_date(:from, default: Date.current.beginning_of_year)
    @to   = parse_date(:to,   default: nil)
    @activity = BankAccountActivity.new(@bank_account, from: @from, to: @to)
    @unmatched_lines = @bank_account.bank_transactions.unmatched.count
  end

  def new
    @bank_account = Current.organization.bank_accounts.build
  end

  def create
    @bank_account = Current.organization.bank_accounts.build(bank_account_params)
    if @bank_account.save
      redirect_to bank_accounts_path, notice: "#{@bank_account.name} added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @bank_account.update(bank_account_params)
      redirect_to bank_accounts_path, notice: "#{@bank_account.name} updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def archive
    @bank_account.archive!
    respond_with_moved_row
  end

  def restore
    @bank_account.restore!
    respond_with_moved_row
  end

  private

  def load_bank_account
    @bank_account = Current.organization.bank_accounts.find(params[:id])
  end

  # Blank means "no bound"; ?from= with nothing after it shows all time.
  def parse_date(key, default:)
    return default unless params.key?(key)
    params[key].present? ? Date.parse(params[key]) : nil
  rescue ArgumentError
    default
  end

  def bank_account_params
    params.require(:bank_account).permit(:name, :code, :kind, :institution, :last_four, :description)
  end

  # The row hops between the active and archived tables in place.
  def respond_with_moved_row
    respond_to do |format|
      format.turbo_stream { render :move }
      format.html { redirect_to bank_accounts_path, notice: "#{@bank_account.name} #{@bank_account.archived? ? 'archived' : 'restored'}." }
    end
  end
end

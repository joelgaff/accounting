class BankTransactionsController < ApplicationController
  before_action :require_login
  before_action :load_transaction, only: %i[match_invoice match_expense categorize ignore]

  def index
    scope = Current.organization.bank_transactions.includes(:bank_account, :matched)
    scope = scope.where(status: params[:status]) if params[:status].in?(BankTransaction::STATUSES)
    scope = scope.where(bank_account_id: params[:bank_account_id]) if params[:bank_account_id].present?
    @transactions   = scope.order(posted_on: :desc, id: :desc)
    @bank_accounts  = Plutus::Asset.where(tenant: Current.organization).order(:code, :name)
    @expense_accts  = Plutus::Expense.where(tenant: Current.organization).order(:code, :name)
    @unmatched_count = Current.organization.bank_transactions.unmatched.count
  end

  # Match a deposit to an outstanding invoice → creates a Payment received.
  def match_invoice
    invoice = Current.organization.invoices.find(params[:invoice_id])
    payment = invoice.payments.create!(
      organization: Current.organization,
      amount:       @txn.amount.abs,
      paid_on:      @txn.posted_on,
      bank_account: @txn.bank_account,
      reference:    @txn.reference
    )
    @txn.update!(status: "matched", matched: payment)
    respond_with_updated_row
  end

  # Match a withdrawal to an outstanding expense → creates a Payment made.
  def match_expense
    expense = Current.organization.expenses.find(params[:expense_id])
    payment = expense.payments.create!(
      organization: Current.organization,
      amount:       @txn.amount.abs,
      paid_on:      @txn.posted_on,
      bank_account: @txn.bank_account,
      reference:    @txn.reference
    )
    @txn.update!(status: "matched", matched: payment)
    respond_with_updated_row
  end

  # Categorize a withdrawal as a fresh Expense (already paid from this bank).
  def categorize
    expense_account = Current.organization.plutus_accounts.find(params[:expense_account_id])
    expense = Current.organization.expenses.create!(
      vendor:            @txn.description.presence || "(bank import)",
      incurred_on:       @txn.posted_on,
      paid_from_account: @txn.bank_account,
      expense_account:   expense_account,
      amount:            @txn.amount.abs
    )
    @txn.update!(status: "matched", matched: expense)
    respond_with_updated_row
  end

  def ignore
    @txn.update!(status: "ignored")
    respond_with_updated_row
  end

  private

  def load_transaction
    @txn = Current.organization.bank_transactions.find(params[:id])
  end

  def respond_with_updated_row
    respond_to do |format|
      format.turbo_stream {
        render turbo_stream: [
          turbo_stream.remove(@txn),
          turbo_stream.update("unmatched-count", Current.organization.bank_transactions.unmatched.count.to_s)
        ]
      }
      format.html { redirect_to bank_transactions_path, notice: "Transaction updated." }
    end
  end
end

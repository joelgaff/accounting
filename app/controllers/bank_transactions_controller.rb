class BankTransactionsController < ApplicationController
  before_action :load_transaction, only: %i[match categorize ignore]

  def index
    scope = Current.organization.bank_transactions.includes(:bank_account, :matched)
    scope = scope.where(status: params[:status]) if params[:status].in?(BankTransaction::STATUSES)
    scope = scope.where(bank_account_id: params[:bank_account_id]) if params[:bank_account_id].present?
    @transactions   = scope.order(posted_on: :desc, id: :desc)
    @bank_accounts  = Current.organization.bank_accounts.active.ordered
    @expense_accts  = Plutus::Expense.where(tenant: Current.organization).order(:code, :name)
    @unmatched_count = Current.organization.bank_transactions.unmatched.count
  end

  # Settle an outstanding invoice or bill with this statement line.
  def match
    document = Current.organization.documents.find(params[:document_id])
    payment  = document.payments.create!(
      organization: Current.organization,
      amount:       @txn.amount.abs,
      paid_on:      @txn.posted_on,
      bank_account: @txn.bank_account,
      reference:    @txn.reference
    )
    @txn.update!(status: "matched", matched: payment)
    respond_with_updated_row
  end

  # Record a withdrawal as a fresh expense paid from this bank.
  def categorize
    expense_account = Current.organization.plutus_accounts.find(params[:expense_account_id])
    document = Current.organization.documents.create!(
      date:         @txn.posted_on,
      reference:    @txn.reference,
      documentable: Expense.new(vendor: @txn.description.presence || "(bank import)", bank_account: @txn.bank_account),
      line_items_attributes: [ { description: @txn.description.to_s, quantity: 1, unit_amount: @txn.amount.abs, account: expense_account } ]
    )
    @txn.update!(status: "matched", matched: document)
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

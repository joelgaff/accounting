class BankTransactionsController < ApplicationController
  before_action :load_transaction, only: %i[match categorize transfer ignore unmatch]
  before_action :load_collections

  def index
    scope = Current.organization.bank_transactions.includes(:bank_account, matched: :documentable)
    scope = scope.where(status: params[:status]) if params[:status].in?(BankTransaction::STATUSES)
    scope = scope.where(bank_account_id: params[:bank_account_id]) if params[:bank_account_id].present?
    @transactions    = scope.order(posted_on: :desc, id: :desc)
    @candidates      = Reconciliation::Candidates.new(Current.organization, @transactions)
    @unmatched_count = Current.organization.bank_transactions.unmatched.count
  end

  # Settle an invoice or bill, or link an existing expense, deposit or transfer.
  def match
    document = Current.organization.documents.find(params[:document_id])
    respond_with_row { Reconciliation::MatchDocument.new(@txn, document).call }
  end

  # A fresh expense (money out) or deposit (money in) for this line.
  def categorize
    respond_with_row do
      Reconciliation::Categorize.new(
        @txn,
        account:      Current.organization.plutus_accounts.find(params[:account_id]),
        tax_rate:     params[:tax_rate_id].present? ? Current.organization.tax_rates.find(params[:tax_rate_id]) : nil,
        contact_name: params[:contact_name],
        memo:         params[:memo]
      ).call
    end
  end

  # Money moved to or from another of our accounts; the mirror line is linked too.
  def transfer
    respond_with_row do
      if params[:transfer_document_id].present?
        Reconciliation::MatchDocument.new(@txn, Current.organization.documents.transfers.find(params[:transfer_document_id])).call
      else
        other = Current.organization.bank_accounts.active.find(params[:other_bank_account_id])
        Reconciliation::CreateTransfer.new(@txn, other_bank_account: other).call
      end
    end
  end

  def ignore
    respond_with_row { @txn.update!(status: "ignored"); Reconciliation::Result.new(transaction: @txn) }
  end

  # An ignored line comes back to the queue. Undo for matched lines lands with split matching.
  def unmatch
    respond_with_row do
      raise Reconciliation::MatchDocument::Mismatch, "only ignored lines can be undone for now" unless @txn.ignored?
      @txn.unlink!
      Reconciliation::Result.new(transaction: @txn)
    end
  end

  private

  def load_transaction
    @txn = Current.organization.bank_transactions.find(params[:id])
  end

  def load_collections
    org = Current.organization
    # Loaded once: the row partials render these for every line on the page.
    @bank_accounts = org.bank_accounts.active.ordered.to_a
    @expense_accts = Plutus::Expense.where(tenant: org).order(:code, :name).to_a
    @income_accts  = org.plutus_accounts.where.not(id: org.bank_accounts.select(:account_id))
                        .order(Arel.sql("CASE type WHEN 'Plutus::Revenue' THEN 0 ELSE 1 END"), :code, :name).to_a
    @tax_rates     = org.tax_rates.ordered.to_a
    @contact_names = org.contacts.ordered.pluck(:name)
  end

  def respond_with_row
    result = yield
    @txn   = result.transaction.reload
    @sibling = result.sibling&.reload
    @candidates = Reconciliation::Candidates.new(Current.organization, [ @txn, @sibling ].compact)
    respond_to do |format|
      format.turbo_stream { render :row }
      format.html { redirect_to bank_transactions_path, notice: "Transaction updated." }
    end
  rescue Reconciliation::MatchDocument::Mismatch, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(helpers.dom_id(@txn, :error), partial: "bank_transactions/error", locals: { txn: @txn, message: e.message }),
               status: :unprocessable_entity
      end
      format.html { redirect_to bank_transactions_path, alert: e.message }
    end
  end
end

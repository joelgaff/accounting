class BankTransactionsController < ApplicationController
  include Paginatable

  before_action :load_transaction, only: %i[match allocate categorize transfer accept_suggestion ignore unmatch]
  before_action :load_collections

  def index
    scope = Current.organization.bank_transactions.includes(:bank_account, :payments, :bank_rule, document: :documentable)
    scope = scope.where(status: params[:status]) if params[:status].in?(BankTransaction::STATUSES)
    scope = scope.where(bank_account_id: params[:bank_account_id]) if params[:bank_account_id].present?
    @transactions    = paginate(scope.order(posted_on: :desc, id: :desc), per: 100)
    @candidates      = Reconciliation::Candidates.new(Current.organization, @transactions)
    @suggestions     = Reconciliation::Suggester.new(Current.organization, @transactions, candidates: @candidates)
    @summary         = Reconciliation::Summary.new(Current.organization).rows
    @unmatched_count = Current.organization.bank_transactions.unmatched.count
  end

  # Settle an invoice or bill (fully or with the amount given), or link an
  # existing expense, deposit or transfer.
  def match
    document = Current.organization.documents.find(params[:document_id])
    respond_with_row { Reconciliation::MatchDocument.new(@txn, document, amount: params[:amount]).call }
  end

  # Split the line across several invoices or bills, sweeping the rest into a
  # new expense or deposit when asked.
  def allocate
    allocations = params.fetch(:allocations, {}).values.map { |a| a.permit(:document_id, :amount).to_h }
    remainder   = params[:remainder]&.permit(:account_id, :tax_rate_id, :contact_name)&.to_h
    respond_with_row { Reconciliation::Allocate.new(@txn, allocations: allocations, remainder: remainder).call }
  end

  # A fresh expense (money out) or deposit (money in) for what is left of this line.
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

  # The one-click OK on the row's top suggestion. The server re-checks everything.
  def accept_suggestion
    org = Current.organization
    respond_with_row do
      case params[:kind]
      when "document", "transfer_side"
        Reconciliation::MatchDocument.new(@txn, org.documents.find(params[:target_id])).call
      when "transfer_pair"
        other = org.bank_transactions.find(params[:target_id]).bank_account
        Reconciliation::CreateTransfer.new(@txn, other_bank_account: other).call
      when "rule"
        org.bank_rules.find(params[:target_id]).apply!(@txn)
      else
        raise Reconciliation::MatchDocument::Mismatch, "unknown suggestion"
      end
    end
  end

  def ignore
    respond_with_row { @txn.update!(status: "ignored"); Reconciliation::Result.new(transaction: @txn) }
  end

  # Back to the queue: payments unwound, a reconcile-made document removed.
  def unmatch
    respond_with_row { Reconciliation::Unmatch.new(@txn).call }
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
    result   = yield
    @txn     = result.transaction.reload
    @sibling = result.sibling&.reload
    rows     = [ @txn, @sibling ].compact
    @candidates  = Reconciliation::Candidates.new(Current.organization, rows)
    @suggestions = Reconciliation::Suggester.new(Current.organization, rows, candidates: @candidates)
    @summary     = Reconciliation::Summary.new(Current.organization).rows.select { |r| rows.map(&:bank_account_id).include?(r.bank_account.id) }
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

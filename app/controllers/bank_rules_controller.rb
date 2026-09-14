class BankRulesController < ApplicationController
  before_action :load_rule, only: %i[edit update destroy]
  before_action :load_collections, only: %i[new create edit update]

  def index
    @rules = Current.organization.bank_rules.ordered.includes(:bank_account, :account, :contact, :transfer_bank_account)
  end

  def new
    @rule = Current.organization.bank_rules.build(prefill)
  end

  def create
    @rule = Current.organization.bank_rules.build(rule_params)
    assign_account
    @rule.position = (Current.organization.bank_rules.maximum(:position) || 0) + 1
    if @rule.save
      redirect_to bank_rules_path, notice: "Rule added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    @rule.assign_attributes(rule_params)
    assign_account
    if @rule.save
      redirect_to bank_rules_path, notice: "Rule updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @rule.destroy
    redirect_to bank_rules_path, notice: "Rule removed."
  end

  private

  def load_rule
    @rule = Current.organization.bank_rules.find(params[:id])
  end

  def load_collections
    org = Current.organization
    @bank_accounts = org.bank_accounts.active.ordered.to_a
    @accounts      = org.plutus_accounts.where.not(id: org.bank_accounts.select(:account_id)).order(:type, :code, :name).to_a
    @contacts      = org.contacts.ordered.to_a
    @tax_rates     = org.tax_rates.ordered.to_a
  end

  # "Create a rule from this line": start from what the line shows.
  def prefill
    return { match_kind: "contains", amount_sign: "any", action_kind: "Expense" } if params[:bank_transaction_id].blank?
    txn = Current.organization.bank_transactions.find(params[:bank_transaction_id])
    {
      name:         txn.display_payee.to_s.truncate(40),
      pattern:      txn.display_payee.to_s,
      match_kind:   "contains",
      amount_sign:  txn.deposit? ? "in" : "out",
      action_kind:  txn.deposit? ? "Deposit" : "Expense",
      bank_account: nil
    }
  end

  # The ledger account is looked up in this organisation's chart, never mass-assigned.
  def assign_account
    return unless params[:bank_rule].key?(:account_id)
    @rule.account = Current.organization.plutus_accounts.find_by(id: params[:bank_rule][:account_id])
  end

  def rule_params
    params.require(:bank_rule).permit(:name, :match_kind, :pattern, :amount_sign, :bank_account_id, :action_kind,
                                      :contact_id, :tax_rate_id, :transfer_bank_account_id, :auto_apply, :active, tracking_option_ids: [])
  end
end

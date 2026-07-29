module Reports
  class BaseReport
    def initialize(organization:, from: nil, to: nil)
      @organization = organization
      @from = from
      @to   = to
    end

    attr_reader :organization, :from, :to

    protected

    def accounts_scope
      Plutus::Account.where(tenant: organization)
    end

    # Balance for a single account within the report's date window.
    # Uses debits_balance and credits_balance so we can constrain by entry date.
    def account_balance(account)
      debits  = amounts_for(account, Plutus::DebitAmount)
      credits = amounts_for(account, Plutus::CreditAmount)
      case account
      when Plutus::Asset, Plutus::Expense
        (debits - credits) * (account.contra ? -1 : 1)
      when Plutus::Liability, Plutus::Equity, Plutus::Revenue
        (credits - debits) * (account.contra ? -1 : 1)
      end
    end

    def amounts_for(account, klass)
      rel = klass.where(account_id: account.id).joins(:entry)
      rel = rel.where(plutus_entries: { date: from.. })   if from
      rel = rel.where(plutus_entries: { date: ..to })     if to
      rel.sum(:amount) || BigDecimal("0")
    end
  end
end

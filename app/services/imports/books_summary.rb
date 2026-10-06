module Imports
  # The one-screen picture of the books after an import: counts, trial
  # balance, and the control accounts Settings points at.
  class BooksSummary
    def initialize(organization) = @organization = organization

    def to_h
      s = @organization.settings
      debits  = Plutus::DebitAmount.joins(:account).where(plutus_accounts: { tenant_id: @organization.id }).sum(:amount)
      credits = Plutus::CreditAmount.joins(:account).where(plutus_accounts: { tenant_id: @organization.id }).sum(:amount)
      {
        "accounts"      => @organization.plutus_accounts.count,
        "contacts"      => @organization.contacts.count,
        "invoices"      => @organization.documents.invoices.count,
        "bills"         => @organization.documents.bills.count,
        "expenses"      => @organization.documents.expenses.count,
        "payments"      => Payment.where(organization: @organization).count,
        "journals"      => @organization.documents.journal_entries.count,
        "trial balance" => format("debits %.2f  credits %.2f  %s", debits, credits, debits == credits ? "BALANCED" : "OUT OF BALANCE"),
        "receivable"    => balance_line(s&.receivable_account),
        "payable"       => balance_line(s&.payable_account),
        "bank"          => balance_line(s&.bank_account)
      }
    end

    private

    def balance_line(account)
      return "(not set)" unless account
      format("%s  %.2f", account.name, account.balance)
    end
  end
end

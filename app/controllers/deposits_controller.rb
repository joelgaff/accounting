class DepositsController < DocumentsController
  private

  def documentable_class     = Deposit
  def documentable_permitted = %i[bank_account_id]
  def after_create_path      = deposits_path
  def created_notice         = "Deposit recorded."

  def build_document
    super.tap { |doc| doc.deposit.bank_account ||= Current.organization.settings.bank_account }
  end

  def load_form_collections
    org = Current.organization
    @income_accounts = org.plutus_accounts.where.not(id: org.bank_accounts.select(:account_id))
                          .order(Arel.sql("CASE type WHEN 'Plutus::Revenue' THEN 0 ELSE 1 END"), :code, :name)
    @bank_accounts   = org.bank_accounts.active.ordered
    @customers       = org.contacts.customers.ordered
    @tax_rates       = org.tax_rates.ordered
  end
end

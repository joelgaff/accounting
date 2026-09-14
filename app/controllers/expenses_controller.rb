class ExpensesController < DocumentsController
  private

  def documentable_class     = Expense
  def documentable_permitted = %i[vendor bank_account_id]
  def after_create_path      = expenses_path
  def created_notice         = "Expense recorded."

  def build_document
    super.tap { |doc| doc.expense.bank_account ||= Current.organization.settings.bank_account }
  end

  def load_form_collections
    @expense_accounts = Plutus::Expense.where(tenant: Current.organization).order(:name)
    @bank_accounts    = Current.organization.bank_accounts.active.ordered
    @vendors          = Current.organization.contacts.vendors.ordered
    @tax_rates        = Current.organization.tax_rates.ordered
  end
end

class BillsController < DocumentsController
  private

  def documentable_class     = Bill
  def documentable_permitted = %i[vendor payable_account_id]
  def after_create_path      = bills_path
  def created_notice         = "Bill recorded."

  def build_document
    super.tap { |doc| doc.bill.payable_account ||= Current.organization.settings.payable_account }
  end

  def load_form_collections
    scope = Plutus::Account.where(tenant: Current.organization)
    @expense_accounts   = scope.where(type: "Plutus::Expense").order(:name)
    @liability_accounts = scope.where(type: "Plutus::Liability").order(:code, :name)
    @vendors            = Current.organization.contacts.vendors.ordered
    @tax_rates          = Current.organization.tax_rates.ordered
  end
end

class BillsController < DocumentsController
  before_action -> { require_control_account(:payable_account, "Accounts Payable", "bills") }, only: %i[new create copy]

  private

  def documentable_class     = Bill
  def documentable_permitted = %i[number vendor]
  def index_preloads         = [ { documentable: :payable_account }, { line_items: :account } ]
  def after_create_path      = bills_path
  def created_notice         = "Bill recorded."

  def build_document
    super.tap { |doc| doc.bill.payable_account ||= Current.organization.settings.payable_account }
  end

  def universal_permitted    = super + %i[billable_to_id]   # a cost can be flagged for a customer

  def load_form_collections
    @customers        = Current.organization.contacts.customers.ordered
    scope = Plutus::Account.where(tenant: Current.organization)
    @expense_accounts   = scope.where(type: "Plutus::Expense").order(:name)
    @vendors            = Current.organization.contacts.vendors.ordered
    @tax_rates          = Current.organization.tax_rates.ordered
  end
end

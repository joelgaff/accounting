# Landing page listing every Xero-migration importer with its status.
class ImportsController < ApplicationController
  before_action :require_login

  def index
    org = Current.organization
    @importers = [
      { name: "Chart of Accounts", path: new_chart_of_accounts_import_path,
        run_before: org.plutus_accounts.exists? },
      { name: "Contacts",          path: new_contact_import_path,
        run_before: org.contacts.exists? },
      { name: "Sales Invoices",    path: new_imports_invoices_path,
        run_before: org.invoices.where.not(xero_invoice_number: nil).exists? },
      { name: "Bills (Purchases)", path: new_imports_bills_path,
        run_before: org.expenses.where.not(xero_invoice_number: nil).exists? },
      { name: "Bank Statement",    path: new_imports_bank_path,
        run_before: false } # can't easily tell from a bank txn — leave for user
    ]
  end
end

# Landing page listing every Xero-migration importer with its status.
class ImportsController < ApplicationController
  def index
    org = Current.organization
    @importers = [
      { name: "Chart of Accounts", path: new_chart_of_accounts_import_path,
        run_before: org.plutus_accounts.exists? },
      { name: "Contacts",          path: new_contact_import_path,
        run_before: org.contacts.exists? },
      { name: "Sales Invoices",    path: new_imports_invoices_path,
        run_before: imported?(Invoice, :xero_invoice_number) },
      { name: "Bills (Purchases)", path: new_imports_bills_path,
        run_before: imported?(Bill, :xero_invoice_number) },
      { name: "Journal Report (full history)", path: new_imports_journals_path,
        run_before: imported?(JournalEntry, :xero_journal_number) },
      { name: "Tax Rates",         path: new_imports_tax_rates_path,
        run_before: org.tax_rates.exists? },
      { name: "Bank Statement",    path: new_imports_bank_path,
        run_before: false } # can't easily tell from a bank txn — leave for user
    ]
  end

  private

  def imported?(type, column)
    type.joins(:document).where(documents: { organization_id: Current.organization.id }).where.not(column => nil).exists?
  end
end

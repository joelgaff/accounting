module Imports
  class XeroInvoicesService < XeroTransactionsService
    private

    def transaction_class = Invoice
    def contact_kind      = "customer"

    def settings_ready?
      @organization.settings.receivable_account.present?
    end

    def settings_error_message
      "Set a receivable account under Settings before importing sales invoices."
    end

    def upsert_record!(number:, header_row:, lines:)
      contact  = resolve_contact(header_row["contactname"])
      document = find_existing(number) || @organization.documents.build(documentable: Invoice.new(xero_invoice_number: number))
      was_new  = document.new_record?

      document.assign_attributes(
        contact:   contact,
        date:      BaseService.parse_xero_date(header_row["invoicedate"]),
        reference: header_row["reference"].to_s.strip.presence
      )
      document.invoice.assign_attributes(
        client_name:        contact.name,
        due_date:           BaseService.parse_xero_date(header_row["duedate"]),
        receivable_account: @organization.settings.receivable_account
      )
      replace_lines!(document, lines, was_new: was_new)
      document
    end
  end
end

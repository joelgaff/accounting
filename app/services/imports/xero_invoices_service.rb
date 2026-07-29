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
      contact = resolve_contact(header_row["contactname"])

      invoice = @organization.invoices.find_or_initialize_by(xero_invoice_number: number)
      was_new = invoice.new_record?

      invoice.assign_attributes(
        contact:            contact,
        client_name:        contact.name,
        due_date:           BaseService.parse_xero_date(header_row["duedate"]),
        receivable_account: @organization.settings.receivable_account,
        reference:          header_row["reference"].to_s.strip.presence
      )
      unless was_new
        invoice.line_items.destroy_all
        Ledger.reset_for(invoice)
      end
      lines.each { |attrs| invoice.line_items.build(attrs) }
      invoice.save!
      invoice.send(:post_to_ledger) unless was_new   # after_create handles the new-record path
      invoice
    end
  end
end

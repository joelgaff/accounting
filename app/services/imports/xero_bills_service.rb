module Imports
  class XeroBillsService < XeroTransactionsService
    private

    def transaction_class = Bill
    def contact_kind      = "vendor"

    def settings_ready?
      @organization.settings.payable_account.present?
    end

    def settings_error_message
      "Set an accounts-payable account under Settings before importing bills."
    end

    def upsert_record!(number:, header_row:, lines:)
      contact  = resolve_contact(header_row["contactname"])
      document = find_existing(number) || @organization.documents.build(documentable: Bill.new(xero_invoice_number: number))
      was_new  = document.new_record?

      document.assign_attributes(
        contact:   contact,
        date:      BaseService.parse_xero_date(header_row["invoicedate"]),
        reference: header_row["reference"].to_s.strip.presence
      )
      document.bill.assign_attributes(
        vendor:          contact.name,
        payable_account: @organization.settings.payable_account   # bills accrue as AP
      )
      replace_lines!(document, lines, was_new: was_new)
      document
    end
  end
end

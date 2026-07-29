module Imports
  class XeroBillsService < XeroTransactionsService
    private

    def transaction_class = Expense
    def contact_kind      = "vendor"

    def settings_ready?
      @organization.settings.payable_account.present?
    end

    def settings_error_message
      "Set an accounts-payable account under Settings before importing bills."
    end

    def upsert_record!(number:, header_row:, lines:)
      contact = resolve_contact(header_row["contactname"])

      expense = @organization.expenses.find_or_initialize_by(xero_invoice_number: number)
      was_new = expense.new_record?

      expense.assign_attributes(
        contact:           contact,
        vendor:            contact.name,
        incurred_on:       BaseService.parse_xero_date(header_row["invoicedate"]),
        paid_from_account: @organization.settings.payable_account,   # bills accrue as AP
        reference:         header_row["reference"].to_s.strip.presence
      )
      unless was_new
        expense.line_items.destroy_all
        Ledger.reset_for(expense)
      end
      lines.each { |attrs| expense.line_items.build(attrs) }
      expense.save!
      expense.send(:post_to_ledger) unless was_new
      expense
    end
  end
end

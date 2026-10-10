module Billing
  # The invoice lines for billable costs picked up on an invoice: one line per
  # expense line, marked up on the unit price, tax and tracking carried across,
  # the account from Settings or the cost's own. Built on the invoice, not saved;
  # the form shows them and the save stores them like any other line.
  class PickUp
    def initialize(invoice, costs, markup: 0)
      @invoice = invoice
      @costs   = Array(costs)
      @factor  = 1 + markup.to_s.strip.to_d / 100
      @account = invoice.organization.settings.billable_income_account
    end

    def lines
      eligible.flat_map do |cost|
        cost.line_items.map do |src|
          line = @invoice.line_items.build(description: src.description, quantity: src.quantity,
                                           unit_amount: marked_up(src.unit_amount), account: @account || src.account,
                                           tax_rate: src.tax_rate, rebills: cost)
          src.copy_tracking_to(line)
          line
        end
      end
    end

    private

    # The customer's own, unbilled costs; anything else offered is ignored.
    def eligible
      @costs.select { |c| c.billable_to && c.billable_to == @invoice.contact && !c.billed? }
    end

    def marked_up(amount) = (amount.to_d * @factor).round(2)
  end
end

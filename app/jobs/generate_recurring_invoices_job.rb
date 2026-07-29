class GenerateRecurringInvoicesJob < ApplicationJob
  queue_as :default

  def perform(as_of: Date.current)
    Organization.find_each do |org|
      Current.organization = org
      org.recurring_invoices.due(as_of).find_each do |ri|
        ri.generate!(as_of: as_of)
      end
    end
  end
end

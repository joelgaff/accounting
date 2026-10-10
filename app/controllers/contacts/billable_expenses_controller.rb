# The panel under an invoice's lines: a customer's unbilled billable costs,
# each with its invoice rows ready to add, marked up as asked.
class Contacts::BillableExpensesController < ApplicationController
  def index
    @contact = Current.organization.contacts.find(params[:contact_id])
    @markup  = params[:markup].to_s.strip.presence || "0"
    @costs   = Current.organization.documents.billable_to(@contact).unbilled.chronological
                      .includes(:contact, :documentable, line_items: [ :account, :tax_rate, { tracking_selections: :tracking_option } ])
    @invoice = Current.organization.documents.build(contact: @contact, documentable: Invoice.new)
    @rows    = @costs.index_with { |cost| Billing::PickUp.new(@invoice, [ cost ], markup: @markup).lines }
    revenue  = Plutus::Revenue.where(tenant: Current.organization).order(:name).to_a
    @accounts  = (revenue + @rows.values.flatten.map(&:account)).uniq
    @tax_rates = Current.organization.tax_rates.ordered
  end
end

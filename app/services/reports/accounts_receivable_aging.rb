module Reports
  class AccountsReceivableAging < BaseReport
    BUCKETS = ["Current", "1-30", "31-60", "61-90", "90+"].freeze

    Row = Struct.new(:contact_name, :buckets, :total, keyword_init: true)

    def initialize(organization:, as_of: Date.current)
      super(organization: organization, from: nil, to: as_of)
      @as_of = as_of
    end
    attr_reader :as_of

    def rows
      @rows ||= outstanding_invoices
        .group_by { |inv| inv.customer_display }
        .map { |name, invs| build_row(name, invs) }
        .sort_by { |r| -r.total }
    end

    def totals_by_bucket
      @totals_by_bucket ||= BUCKETS.index_with do |b|
        rows.sum { |r| r.buckets[b] || BigDecimal("0") }
      end
    end

    def grand_total = rows.sum(&:total)

    private

    def outstanding_invoices
      organization.invoices.includes(:contact, :payments)
                  .select { |inv| inv.balance_due.positive? }
    end

    def build_row(name, invs)
      buckets = Hash.new(BigDecimal("0"))
      total   = BigDecimal("0")
      invs.each do |inv|
        b = bucket_for(inv.due_date)
        buckets[b] += inv.balance_due
        total     += inv.balance_due
      end
      Row.new(contact_name: name, buckets: buckets, total: total)
    end

    def bucket_for(due_date)
      days = (as_of - due_date).to_i
      return "Current" if days <= 0
      return "1-30"    if days <= 30
      return "31-60"   if days <= 60
      return "61-90"   if days <= 90
      "90+"
    end
  end
end

module Reports
  class AccountsPayableAging < BaseReport
    BUCKETS = [ "Current", "1-30", "31-60", "61-90", "90+" ].freeze

    Row = Struct.new(:contact_name, :buckets, :total, keyword_init: true)

    def initialize(organization:, as_of: Date.current)
      super(organization: organization, from: nil, to: as_of)
      @as_of = as_of
    end
    attr_reader :as_of

    def rows
      @rows ||= outstanding_bills
        .group_by { |bill| bill.counterparty }
        .map { |name, exps| build_row(name, exps) }
        .sort_by { |r| -r.total }
    end

    def totals_by_bucket
      @totals_by_bucket ||= BUCKETS.index_with do |b|
        rows.sum { |r| r.buckets[b] || BigDecimal("0") }
      end
    end

    def grand_total = rows.sum(&:total)

    private

    def outstanding_bills
      payable = organization.settings.payable_account
      return [] unless payable
      organization.documents.bills.includes(:contact, :payments, :documentable)
                  .select { |bill| bill.bill.payable_account_id == payable.id && bill.balance_due.positive? }
    end

    def build_row(name, exps)
      buckets = Hash.new(BigDecimal("0"))
      total   = BigDecimal("0")
      exps.each do |bill|
        # Bills don't carry a due date yet; treat them as due 30 days after the bill date.
        b = bucket_for(bill.date + 30)
        buckets[b] += bill.balance_due
        total     += bill.balance_due
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

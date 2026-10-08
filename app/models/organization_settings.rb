class OrganizationSettings < ApplicationRecord
  belongs_to :organization
  belongs_to :bank_account,       optional: true
  belongs_to :receivable_account, class_name: "Plutus::Asset",     optional: true
  belongs_to :payable_account,    class_name: "Plutus::Liability", optional: true

  scoped_to_organization :bank_account, :receivable_account, :payable_account, organization: ->(s) { s.organization }

  NUMBER_WIDTH = 4   # INV-0001; the digits grow past four on their own

  normalizes :invoice_prefix, with: ->(p) { p.to_s.strip }
  validates :invoice_next_number, numericality: { only_integer: true, greater_than_or_equal_to: 1 }, allow_nil: true
  validate  :control_accounts_stay_set

  # A control account may change, but not go blank while documents post to it.
  def control_accounts_stay_set
    if receivable_account_id.nil? && receivable_account_id_was.present? && organization.documents.invoices.exists?
      errors.add(:receivable_account, "can't be cleared while invoices post to it; pick another account instead")
    end
    if payable_account_id.nil? && payable_account_id_was.present? && organization.documents.bills.exists?
      errors.add(:payable_account, "can't be cleared while bills post to it; pick another account instead")
    end
  end

  # The number the next invoice gets: the prefix plus the next number, or,
  # until one is set, one past the highest invoice already carrying the prefix.
  def next_invoice_number
    "#{invoice_prefix}#{format("%0#{NUMBER_WIDTH}d", invoice_next_number || highest_invoice_number_in_sequence + 1)}"
  end

  # An invoice was saved with this number: if it is in our sequence, the
  # sequence moves past it. Numbers under another prefix are not ours.
  def advance_invoice_sequence!(number)
    n = number_within_sequence(number) or return
    current = invoice_next_number || highest_invoice_number_in_sequence + 1
    update!(invoice_next_number: [ current, n + 1 ].max)
  end

  private

  def number_within_sequence(number)
    m = number.to_s.match(/\A#{Regexp.escape(invoice_prefix)}(\d+)\z/) or return nil
    m[1].to_i
  end

  def highest_invoice_number_in_sequence
    Invoice.joins(:document).where(documents: { organization_id: organization_id }).where.not(number: nil)
           .pluck(:number).filter_map { |n| number_within_sequence(n) }.max || 0
  end
end

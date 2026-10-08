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

  # Which documents post to each control account.
  CONTROL_ACCOUNTS = { receivable_account: :invoices, payable_account: :bills }.freeze

  # A control account may change, but not go blank while documents post to it.
  def control_accounts_stay_set
    CONTROL_ACCOUNTS.each do |attr, documents|
      next unless public_send("#{attr}_id").nil? && public_send("#{attr}_id_was").present?
      next unless organization.documents.public_send(documents).exists?
      errors.add(attr, "can't be cleared while #{documents} post to it; pick another account instead")
    end
  end

  # The number the next invoice gets: the prefix plus the first free number at
  # or after the counter. Until a counter is set, that is one past the highest
  # invoice already carrying the prefix.
  def next_invoice_number
    "#{invoice_prefix}#{format("%0#{NUMBER_WIDTH}d", first_free_invoice_number)}"
  end

  # An invoice was saved with this number: if it is in our sequence, the
  # counter moves to the next free number past it. Numbers under another
  # prefix are not ours.
  def advance_invoice_sequence!(number)
    n = number_within_sequence(number) or return
    update!(invoice_next_number: first_free_invoice_number(from: [ first_free_invoice_number, n + 1 ].max))
  end

  private

  def number_within_sequence(number)
    m = number.to_s.match(/\A#{Regexp.escape(invoice_prefix)}(\d+)\z/) or return nil
    m[1].to_i
  end

  # Every number under the prefix that an invoice already carries.
  def used_invoice_numbers
    Invoice.joins(:document).where(documents: { organization_id: organization_id }).where.not(number: nil)
           .pluck(:number).filter_map { |n| number_within_sequence(n) }
  end

  def first_free_invoice_number(from: nil)
    used = used_invoice_numbers.to_set
    n = from || invoice_next_number || (used.max || 0) + 1
    n += 1 while used.include?(n)
    n
  end
end

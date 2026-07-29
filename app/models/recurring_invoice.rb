class RecurringInvoice < ApplicationRecord
  FREQUENCIES = %w[weekly monthly yearly].freeze

  belongs_to :organization
  belongs_to :contact,            optional: true
  belongs_to :receivable_account, class_name: "Plutus::Asset"
  has_many   :line_items, -> { ordered }, as: :lineable, dependent: :destroy, inverse_of: :lineable
  accepts_nested_attributes_for :line_items, allow_destroy: true, reject_if: :all_blank

  before_validation :sync_client_name_from_contact
  validates :client_name, :frequency, :next_run_on, presence: true
  validates :frequency, inclusion: { in: FREQUENCIES }
  validates :interval,  numericality: { greater_than: 0 }
  validates :net_days,  numericality: { greater_than_or_equal_to: 0 }

  scope :due, ->(as_of = Date.current) { active.where("next_run_on <= ?", as_of).where("end_on IS NULL OR end_on >= ?", as_of) }
  scope :active, -> { where(active: true) }

  def customer_display = contact&.name.presence || client_name

  # Materialize one real Invoice for the current period and advance the schedule.
  def generate!(as_of: Date.current)
    ActiveRecord::Base.transaction do
      invoice = organization.invoices.build(
        contact:            contact,
        client_name:        client_name,
        due_date:           as_of + net_days.days,
        receivable_account: receivable_account,
        reference:          "Recurring ##{id}"
      )
      line_items.each do |src|
        invoice.line_items.build(
          description: src.description, quantity: src.quantity,
          unit_amount: src.unit_amount, account: src.account, tax_rate: src.tax_rate
        )
      end
      invoice.save!

      # Advance schedule
      self.next_run_on = advance(next_run_on)
      self.active      = false if end_on && next_run_on > end_on
      save!

      # Optional auto-email
      if email_on_generate && contact&.email.present?
        InvoiceMailer.send_invoice(invoice, to: contact.email).deliver_later
      end

      invoice
    end
  end

  private

  def sync_client_name_from_contact
    self.client_name = contact.name if contact && client_name.blank?
  end

  def advance(date)
    case frequency
    when "weekly"  then date + (7 * interval).days
    when "monthly" then date + interval.months
    when "yearly"  then date + interval.years
    end
  end
end

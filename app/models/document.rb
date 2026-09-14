# Every transaction that posts to the ledger is a Document: one row on the
# shared timeline (organisation, contact, date, reference, totals) plus a
# delegated type carrying what only that kind of transaction has.
#
# The type answers the questions that differ per kind — ledger legs, status,
# whether it can take payments — and Document does everything shared: line
# items, totals, payments, attachments and posting to the ledger.
class Document < ApplicationRecord
  TYPES = %w[Invoice Bill Expense Deposit Transfer JournalEntry].freeze
  SOURCES = %w[manual reconcile xero_import].freeze

  include HasLineItems
  include HasBalanceDue
  include DocumentHistory

  belongs_to :organization
  belongs_to :contact, optional: true
  delegated_type :documentable, types: TYPES, dependent: :destroy, autosave: true, inverse_of: :document
  has_many :entries, class_name: "Plutus::Entry", as: :commercial_document
  has_many :bank_transactions, dependent: :nullify
  has_many_attached :attachments

  before_validation :default_date
  before_validation :link_documentable
  before_validation :sync_totals
  validates :date, presence: true
  validates :source, inclusion: { in: SOURCES }
  validates :total, numericality: { greater_than: 0 }
  validate  :must_have_line_items, if: -> { documentable&.line_items? }
  validate  :not_voided,             on: :update
  validate  :total_covers_payments,  on: :update
  validate  :total_matches_bank_line, on: :update

  after_create :post_to_ledger

  scope :chronological, -> { order(date: :desc, id: :desc) }
  scope :live,   -> { where(voided_at: nil) }
  scope :voided, -> { where.not(voided_at: nil) }
  scope :outstanding_between, ->(low, high) {
    where("(documents.total - COALESCE((SELECT SUM(payments.amount) FROM payments WHERE payments.document_id = documents.id), 0)) BETWEEN ? AND ?", low, high)
  }

  # Lets a form post document[documentable_attributes][...] into the type record
  # the controller already built (documents.build(documentable: Invoice.new)).
  def documentable_attributes=(attrs)
    documentable.assign_attributes(attrs)
  end

  delegate :settleable?, :party_name, to: :documentable

  def status  = voided? ? "voided" : documentable.status
  def voided? = voided_at.present?

  def label        = "#{documentable.model_name.human} ##{id}"
  def counterparty = contact&.name.presence || party_name
  def display_name = counterparty.presence || memo.to_s.truncate(40).presence || label

  # Wipe this document's posting and post it again from what it holds now.
  # Used by the importers when a re-import changes a document in place.
  def repost_to_ledger!
    transaction do
      Ledger.reset_for(self)
      post_to_ledger
    end
  end

  # Edit in place: new attributes and lines, then a fresh posting.
  def update_and_repost!(attrs)
    transaction do
      before = history_snapshot
      assign_attributes(attrs)
      save!
      line_items.reload if documentable.line_items?
      repost_to_ledger!
      record_edit_against!(before)
    end
  end

  # "This never happened": unwind every payment against it, release every
  # statement line pointing at it, remove its postings, and mark it. The
  # document itself stays for the record.
  def void!
    raise ActiveRecord::RecordInvalid.new(self) if voided?
    transaction do
      consequences = void_consequences
      payments.each { |p| p.unwind!(record: false) }
      bank_transactions.each(&:unlink!)
      Ledger.reset_for(self)
      update_columns(voided_at: Time.current, updated_at: Time.current)
      record_event!(:voided, **consequences)
    end
  end

  # What void! would touch, for the confirmation prompt.
  def void_consequences
    { payments: payments.size, paid: paid_amount,
      bank_lines: (bank_transactions.pluck(:id) + payments.filter_map(&:bank_transaction_id)).uniq.size }
  end

  private

  def default_date
    self.date ||= Date.current
  end

  # A freshly built type record needs to see its document (contact, lines)
  # inside its own validations before either side is saved.
  def link_documentable
    return if documentable.nil? || !documentable.new_record? || documentable.document
    documentable.document = self
  end

  def sync_totals
    return if documentable.nil?
    self.subtotal, self.tax_amount = documentable.totals_for(self)
    self.total = subtotal.to_d + tax_amount.to_d
  end

  def must_have_line_items
    errors.add(:base, "must have at least one line item") if live_line_items.empty?
  end

  def not_voided
    errors.add(:base, "is voided and can't be changed") if voided?
  end

  def total_covers_payments
    return unless settleable? && total_changed?
    paid = paid_amount
    errors.add(:total, "can't be below the $#{'%.2f' % paid} already paid") if total < paid
  end

  # A document created from or linked to a statement line must keep that
  # line's amount; unmatch the line first to change it.
  def total_matches_bank_line
    return unless total_changed?
    line = bank_transactions.first
    return if line.nil? || line.amount.abs == total
    errors.add(:total, "must stay $#{'%.2f' % line.amount.abs} while matched to a bank line (unmatch it first)")
  end

  def post_to_ledger
    legs = documentable.ledger_legs(self)
    Ledger.post(
      description: documentable.ledger_description(self),
      date: date,
      commercial_document: self,
      debits: legs[:debits],
      credits: legs[:credits]
    )
  end
end

# Every transaction that posts to the ledger is a Document: one row on the
# shared timeline (organisation, contact, date, reference, totals) plus a
# delegated type carrying what only that kind of transaction has.
#
# The type answers the questions that differ per kind — ledger legs, status,
# whether it can take payments — and Document does everything shared: line
# items, totals, payments, attachments and posting to the ledger.
class Document < ApplicationRecord
  TYPES = %w[Invoice Bill Expense JournalEntry].freeze

  include HasLineItems
  include HasBalanceDue

  belongs_to :organization
  belongs_to :contact, optional: true
  delegated_type :documentable, types: TYPES, dependent: :destroy, autosave: true, inverse_of: :document
  has_many :entries, class_name: "Plutus::Entry", as: :commercial_document
  has_many_attached :attachments

  before_validation :default_date
  before_validation :link_documentable
  before_validation :sync_totals
  validates :date, presence: true
  validates :total, numericality: { greater_than: 0 }
  validate  :must_have_line_items, if: -> { documentable&.line_items? }

  after_create :post_to_ledger

  scope :chronological, -> { order(date: :desc, id: :desc) }
  scope :outstanding_between, ->(low, high) {
    where("(documents.total - COALESCE((SELECT SUM(payments.amount) FROM payments WHERE payments.document_id = documents.id), 0)) BETWEEN ? AND ?", low, high)
  }

  # Lets a form post document[documentable_attributes][...] into the type record
  # the controller already built (documents.build(documentable: Invoice.new)).
  def documentable_attributes=(attrs)
    documentable.assign_attributes(attrs)
  end

  delegate :status, :settleable?, :party_name, to: :documentable

  def label        = "#{documentable.model_name.human} ##{id}"
  def counterparty = contact&.name.presence || party_name

  # Wipe this document's posting and post it again from what it holds now.
  # Used by the importers when a re-import changes a document in place.
  def repost_to_ledger!
    transaction do
      Ledger.reset_for(self)
      post_to_ledger
    end
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

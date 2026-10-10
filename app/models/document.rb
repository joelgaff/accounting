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

  attr_accessor :created_via   # noted in the history: "memory" when reconcile coded it from past codings
  attr_accessor :contact_name  # a name typed on a form: the contact is found or made before validation
  attr_accessor :copied_from_id # the document this one was copied from, noted in the history

  belongs_to :organization
  belongs_to :contact, optional: true
  belongs_to :billable_to, class_name: "Contact", optional: true   # the customer an expense or bill will be invoiced to
  delegated_type :documentable, types: TYPES, dependent: :destroy, autosave: true, inverse_of: :document
  has_many :entries, class_name: "Plutus::Entry", as: :commercial_document
  has_many :bank_transactions, dependent: :nullify
  has_many :rebilling_lines, class_name: "LineItem", foreign_key: :rebills_document_id, dependent: :nullify, inverse_of: :rebills
  has_many_attached :attachments

  before_validation :default_date
  before_validation :link_documentable
  before_validation :contact_from_name
  before_validation :sync_totals
  scoped_to_organization :contact, :billable_to, organization: ->(doc) { doc.organization }
  enum :state, { draft: "draft", approved: "approved" }, validate: true
  validates :date, presence: true
  validates :source, inclusion: { in: SOURCES }
  # A draft may be empty; lines and a total are what approval requires.
  validates :total, numericality: { greater_than: 0 }, if: :approved?
  validate  :must_have_line_items, if: -> { approved? && documentable&.line_items? }
  validate  :party_named,          if: -> { (expense? || deposit?) && source != "xero_import" }
  validate  :only_purchases_are_billable
  before_save :make_billable_to_a_customer
  validate  :not_voided,             on: :update
  validate  :total_covers_payments,  on: :update
  validate  :total_matches_bank_line, on: :update

  after_create :post_to_ledger, if: :approved?
  before_destroy :refuse_unless_deletable, prepend: true
  before_destroy { Ledger.reset_for(self) }

  scope :chronological, -> { order(date: :desc, id: :desc) }
  scope :live,   -> { where(voided_at: nil) }
  scope :voided, -> { where.not(voided_at: nil) }
  scope :posted, -> { live.approved }   # on the ledger: neither draft nor voided
  scope :billable_to, ->(contact) { posted.where(billable_to: contact) }   # costs flagged for a customer
  scope :unbilled, -> { where.not(id: LineItem.rebilling.select(:rebills_document_id)) }   # no live invoice carries them yet
  scope :outstanding_between, ->(low, high) {
    where("(documents.total - COALESCE((SELECT SUM(payments.amount) FROM payments WHERE payments.document_id = documents.id), 0)) BETWEEN ? AND ?", low, high)
  }

  # Lets a form post document[documentable_attributes][...] into the type record
  # the controller already built (documents.build(documentable: Invoice.new)).
  def documentable_attributes=(attrs)
    documentable.assign_attributes(attrs)
  end

  delegate :settleable?, :party_name, to: :documentable

  def status
    return "voided" if voided?
    return "draft"  if draft?
    documentable.status
  end
  def voided? = voided_at.present?

  # "Invoice INV-2378" when the type carries a number; otherwise what it is and
  # who it was with, "Expense · Zoom", since a row id means nothing to a reader.
  def label
    kind   = documentable.model_name.human
    number = documentable.try(:number).presence
    return "#{kind} #{number}" if number
    detail = counterparty.presence || memo.to_s.truncate(40).presence || documentable.try(:narrative).presence
    detail ? "#{kind} · #{detail}" : kind
  end
  # The label plus the name, for lists where a numbered document needs both.
  def title        = documentable.try(:number).present? ? "#{label} · #{display_name}" : label
  # The memo when someone wrote it; the bank's own words copied onto a
  # reconciled line are not a why and are not worth repeating.
  def why(bank_words = bank_transactions.first&.description) = Document.why_from(memo, bank_words)

  def self.why_from(words, bank_words)
    words = words.to_s.strip
    return nil if words.blank? || words.casecmp?(bank_words.to_s.strip)
    words
  end

  # Fill this new document from another: who it is with, its lines and their tracking,
  # and what the type keeps (the invoice's payment terms, the bill's vendor). Number,
  # dates, state, sent mark, payments, attachments, reference and memo stay with the original.
  def copy_from(original)
    self.contact        = original.contact
    self.copied_from_id = original.id
    original.line_items.each { |src| src.copy_to(self) }
    documentable.copy_from(original.documentable, original: original, document: self)
    self
  end

  def copyable? = documentable.copyable?
  def billable? = expense? || bill?

  # The live invoice carrying a line that rebills this cost, draft or approved; nil when none does.
  def billed_on
    rebilling_lines.includes(:lineable).map(&:lineable).find { |doc| doc.is_a?(Document) && doc.invoice? && !doc.voided? }
  end
  def billed? = billed_on.present?

  def copied_from
    organization.documents.find_by(id: copied_from_id) if copied_from_id.present?
  end

  def counterparty = contact&.name.presence || party_name
  def display_name = counterparty.presence || memo.to_s.truncate(40).presence || label

  # Wipe this document's posting and post it again from what it holds now.
  # Used by the importers when a re-import changes a document in place.
  # A draft has no posting, so there is nothing to redo.
  def repost_to_ledger!
    transaction do
      Ledger.reset_for(self)
      post_to_ledger if approved?
    end
  end

  # A draft becomes real: it posts to the ledger and shows up everywhere.
  def approve!
    raise ActiveRecord::RecordInvalid.new(self) unless draft?
    transaction do
      documentable.take_control_account_from(organization.settings)   # Settings is the truth until it posts
      documentable.validate!          # the type record is checked again, it may have gone stale
      update!(state: "approved")
      post_to_ledger
      record_event!(:approved)
    end
  end

  # Back to the drawing board: only while nothing is settled against it.
  def unapprove!
    raise ActiveRecord::RecordInvalid.new(self) unless approved? && deletable?
    transaction do
      Ledger.reset_for(self)
      update!(state: "draft")
      record_event!(:unapproved)
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

  # Save the edit and approve in one transaction, so a bad edit never
  # leaves a half-approved document behind.
  def update_and_approve!(attrs)
    transaction do
      update_and_repost!(attrs)
      approve! if draft?
    end
  end

  # "This never happened": unwind every payment against it, release every
  # statement line pointing at it, remove its postings, and mark it. The
  # document itself stays for the record.
  def void!
    errors.add(:base, "is a draft; delete it instead") if draft?
    raise ActiveRecord::RecordInvalid.new(self) if voided? || draft?
    transaction do
      consequences = void_consequences
      payments.each { |p| p.unwind!(record: false) }
      bank_transactions.each(&:unlink!)
      Ledger.reset_for(self)
      update_columns(voided_at: Time.current, updated_at: Time.current)
      record_event!(:voided, **consequences)
    end
  end

  # Gone for good is fine when nothing else refers to it: no payments against
  # it and no bank line matched to it. Voiding first detaches both, so
  # anything can be deleted in two steps when that is really wanted.
  def deletable?
    payments.none? && bank_transactions.none?
  end

  # What void! would touch, for the confirmation prompt.
  def void_consequences
    { payments: payments.size, paid: paid_amount,
      bank_lines: (bank_transactions.pluck(:id) + payments.filter_map(&:bank_transaction_id)).uniq.size }
  end

  private

  def only_purchases_are_billable
    errors.add(:billable_to, "applies to expenses and bills only") if billable_to_id.present? && !billable?
  end

  # Whoever a cost is billed to is a customer, whatever they were before.
  def make_billable_to_a_customer
    billable_to.update!(kind: "both") if billable_to && !billable_to.customer?
  end

  def refuse_unless_deletable
    return if deletable?
    errors.add(:base, "has payments or a matched bank line; void it first")
    throw :abort
  end

  def default_date
    self.date ||= Date.current
  end

  # Expenses and deposits name who they were with, as a contact rather than a
  # string. Xero's history is not held to it: some of it never had one.
  def party_named
    errors.add(:contact, "is required: name who this was with") if contact.nil?
  end

  def contact_from_name
    name = contact_name.to_s.strip
    return if name.blank? || contact.present? || organization.nil?
    kind = (expense? || bill?) ? "vendor" : "customer"
    self.contact = Contact.find_or_create_named(organization, name, kind: kind)
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

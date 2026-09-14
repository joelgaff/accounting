# Records a document's history (see DocumentEvent). Creation and voiding are
# captured here; edits diff a snapshot taken before the change; payments,
# emails and reconcile links record themselves from where they happen.
module DocumentHistory
  extend ActiveSupport::Concern

  # Fields shown in an edit diff, with their labels; type-specific attributes
  # are added from the documentable row itself.
  UNIVERSAL_FIELDS = { "date" => "Date", "reference" => "Reference", "memo" => "Memo" }.freeze
  TYPE_FIELD_LABELS = {
    "client_name" => "Customer", "due_date" => "Due date", "vendor" => "Vendor", "narrative" => "Narrative"
  }.freeze
  IGNORED_TYPE_FIELDS = %w[id created_at updated_at xero_invoice_number xero_journal_number xero_source_type].freeze

  included do
    has_many :events, class_name: "DocumentEvent", dependent: :destroy
    after_create :record_created_event
  end

  def record_event!(action, **details)
    events.create!(organization: organization, user: Current.user, action: action.to_s, details: details.compact.as_json)
  end

  # A flat picture of what a reader would see, for diffing around an edit.
  def history_snapshot
    snap = UNIVERSAL_FIELDS.to_h { |col, label| [ label, public_send(col) ] }
    snap["Contact"] = counterparty
    snap["Total"]   = "$#{'%.2f' % total}"
    snap["Lines"]   = documentable.line_items? ? live_line_items.size : nil
    documentable.attributes.except(*IGNORED_TYPE_FIELDS).each do |col, value|
      next if col.end_with?("_id")
      snap[TYPE_FIELD_LABELS.fetch(col, col.humanize)] = value
    end
    documentable.attributes.slice(*documentable.attributes.keys.grep(/_account_id\z|bank_account_id\z/)).each do |col, id|
      label = TYPE_FIELD_LABELS.fetch(col, col.delete_suffix("_id").humanize)
      snap[label] = account_name_for(col, id)
    end
    snap.compact
  end

  def record_edit_against!(before)
    after   = history_snapshot
    changes = (before.keys | after.keys).filter_map do |k|
      from, to = before[k], after[k]
      [ k, [ from, to ].map { |v| v.respond_to?(:strftime) ? v.iso8601 : v } ] unless from.to_s == to.to_s
    end.to_h
    record_event!(:edited, changes: changes) if changes.any?
  end

  private

  def record_created_event
    record_event!(:created, source: source, total: total, reference: reference)
  end

  def account_name_for(col, id)
    return nil if id.nil?
    col.end_with?("bank_account_id") ? BankAccount.find_by(id: id)&.name : Plutus::Account.find_by(id: id)&.name
  end
end

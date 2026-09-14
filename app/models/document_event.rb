# One line of a document's history: who did what, when, with the details a
# reader needs (what changed, how much, to whom). Xero calls this "History &
# Notes"; notes are events too.
class DocumentEvent < ApplicationRecord
  ACTIONS = %w[created edited voided payment_recorded payment_removed emailed matched unmatched imported note].freeze

  belongs_to :document
  belongs_to :organization
  belongs_to :user, optional: true

  validates :action, inclusion: { in: ACTIONS }
  validates :details, presence: true, if: :note?

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  def note? = action == "note"

  def actor_name
    user&.name.presence || user&.email.presence || (details["source"] == "xero_import" ? "Xero import" : "System")
  end

  def title
    case action
    when "created"          then details["source"] == "reconcile" ? "Created from a bank line" : "Created"
    when "edited"           then "Edited"
    when "voided"           then "Voided"
    when "payment_recorded" then "Payment #{details['direction'] == 'made' ? 'made' : 'received'}"
    when "payment_removed"  then "Payment removed"
    when "emailed"          then "Emailed"
    when "matched"          then "Matched to a bank line"
    when "unmatched"        then "Unmatched from a bank line"
    when "imported"         then "Updated by import"
    when "note"             then "Note"
    end
  end

  # Human lines under the title, built from whatever details the event carries.
  def detail_lines
    d = details
    case action
    when "created", "imported"
      [ ("Total #{money d['total']}" if d["total"]), ("Reference #{d['reference']}" if d["reference"].present?) ].compact
    when "edited"
      d.fetch("changes", {}).map { |field, (from, to)| "#{field}: #{blank_or(from)} → #{blank_or(to)}" }
    when "voided"
      [ ("#{d['payments']} payment#{'s' unless d['payments'] == 1} removed (#{money d['paid']})" if d["payments"].to_i.positive?),
        ("#{d['bank_lines']} bank line#{'s' unless d['bank_lines'] == 1} returned to the queue" if d["bank_lines"].to_i.positive?) ].compact
    when "payment_recorded", "payment_removed"
      [ [ money(d["amount"]), d["bank_account"], (d["paid_on"] && "on #{d['paid_on']}"), (d["via"] == "reconcile" ? "via reconcile" : nil) ].compact.join(" · ") ]
    when "emailed"
      [ "To #{d['to']}", ("Subject: #{d['subject']}" if d["subject"].present?), ("PDF attached" if d["pdf"]) ].compact
    when "matched", "unmatched"
      [ [ d["bank_account"], d["posted_on"], (d["amount"] && money(d["amount"])), d["description"] ].compact_blank.join(" · ") ]
    when "note"
      [ d["text"].to_s ]
    else
      []
    end
  end

  private

  def money(v) = "$#{'%.2f' % v.to_d}" rescue v.to_s
  def blank_or(v) = v.nil? || v.to_s.empty? ? "(blank)" : v.to_s
end

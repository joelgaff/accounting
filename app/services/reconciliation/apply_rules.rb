module Reconciliation
  # After an import: rules that auto-apply categorize their lines outright,
  # the others just leave a suggestion on the line.
  class ApplyRules
    Outcome = Struct.new(:applied, :suggested, keyword_init: true)

    def initialize(organization, transactions)
      @org   = organization
      @txns  = Array(transactions)
      @rules = @org.bank_rules.active.ordered.to_a
    end

    def call
      applied = suggested = 0
      @txns.each do |txn|
        next unless txn.unmatched? && txn.document.nil? && txn.payments.none?
        rule = @rules.detect { |r| r.matches?(txn) } or next
        if rule.auto_apply
          rule.apply!(txn, source: "reconcile")
          applied += 1
        else
          txn.update!(bank_rule: rule)
          suggested += 1
        end
      rescue MatchDocument::Mismatch, ActiveRecord::RecordInvalid
        next
      end
      Outcome.new(applied: applied, suggested: suggested)
    end
  end
end

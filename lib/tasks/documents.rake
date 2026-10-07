# Server-side fixes for document state. ORG_ID=n picks the organisation,
# otherwise the single one. DRY_RUN=1 rolls the work back.
#
#   bin/rails documents:audit                       drafts with postings, approved rows without
#   bin/rails 'documents:state[approved,12,13]'     approve drafts (posts them)
#   bin/rails 'documents:state[draft,12]'           back to draft (unposts; refused if settled)
namespace :documents do
  def documents_org
    org = ENV["ORG_ID"].present? ? Organization.find(ENV["ORG_ID"]) : Organization.sole
    Current.organization = org
    org
  end

  desc "List documents whose state disagrees with their ledger postings"
  task audit: :environment do
    org = documents_org
    posted = Plutus::Entry.where(commercial_document_type: "Document").distinct.pluck(:commercial_document_id)
    drafts_with_postings  = org.documents.draft.where(id: posted)
    approved_unposted     = org.documents.approved.where.not(id: posted)
    drafts_with_postings.each  { |d| puts "draft but posted:      #{d.label} (id #{d.id})" }
    approved_unposted.each     { |d| puts "approved but unposted: #{d.label} (id #{d.id})" }
    puts "#{drafts_with_postings.size + approved_unposted.size} mismatch(es) in #{org.name}"
  end

  desc "Set documents to approved or draft by id: documents:state[approved,1,2,3]"
  task :state, [ :state ] => :environment do |_, args|
    state = args[:state].to_s
    ids   = args.extras.map(&:to_i)
    abort "usage: bin/rails 'documents:state[approved|draft,ID,...]'" unless Document.states.key?(state) && ids.any?

    org = documents_org
    ActiveRecord::Base.transaction do
      org.documents.where(id: ids).find_each do |doc|
        if doc.state == state
          puts "#{doc.label} (id #{doc.id}) already #{state}"
        elsif state == "draft" && !doc.deletable?
          puts "#{doc.label} (id #{doc.id}) refused: has payments or a matched bank line; void or unmatch first"
        else
          state == "approved" ? doc.approve! : doc.unapprove!
          puts "#{doc.label} (id #{doc.id}) → #{state}"
        end
      end
      if ENV["DRY_RUN"].present?
        puts "DRY_RUN: rolled back"
        raise ActiveRecord::Rollback
      end
    end
  end
end

require "test_helper"
require "rake"

class DocumentsTasksTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    @ar    = Plutus::Asset.create!(tenant: @org, name: "AR")
    @sales = Plutus::Revenue.create!(tenant: @org, name: "Sales")
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    ENV["ORG_ID"] = @org.id.to_s
  end

  teardown do
    ENV.delete("ORG_ID")
    ENV.delete("DRY_RUN")
  end

  test "documents:audit names drafts with postings and approved documents without" do
    fine     = create_invoice(@org, client_name: "A", amount: 1, receivable: @ar, revenue: @sales)
    bad_draft = create_invoice(@org, client_name: "B", amount: 2, receivable: @ar, revenue: @sales)
    bad_draft.update_columns(state: "draft")                     # approved posting, draft label
    bad_approved = create_invoice(@org, client_name: "C", amount: 3, receivable: @ar, revenue: @sales, state: "draft")
    bad_approved.update_columns(state: "approved")               # no posting, approved label

    out = run_task("documents:audit")
    assert_includes out, "#{bad_draft.label}"
    assert_includes out, "#{bad_approved.label}"
    assert_not_includes out, "#{fine.label}"
  end

  test "documents:state approves drafts and drafts approved documents, and DRY_RUN rolls back" do
    draft = create_invoice(@org, client_name: "A", amount: 1, receivable: @ar, revenue: @sales, state: "draft")
    run_task("documents:state", "approved", draft.id.to_s)
    assert draft.reload.approved?
    assert_equal 1, draft.entries.count

    ENV["DRY_RUN"] = "1"
    run_task("documents:state", "draft", draft.id.to_s)
    assert draft.reload.approved?, "dry run must change nothing"
    ENV.delete("DRY_RUN")

    run_task("documents:state", "draft", draft.id.to_s)
    assert draft.reload.draft?
    assert_equal 0, draft.entries.count
  end

  test "documents:state reports a refusal instead of crashing" do
    bank = create_bank_account(@org, name: "Bank")
    paid = create_invoice(@org, client_name: "A", amount: 10, receivable: @ar, revenue: @sales)
    paid.payments.create!(organization: @org, amount: 10, paid_on: Date.current, bank_account: bank)
    out = run_task("documents:state", "draft", paid.id.to_s)
    assert_includes out, "refused"
    assert_includes out, paid.label
    assert paid.reload.approved?
  end

  private

  def run_task(name, *args)
    task = Rake::Task[name]
    task.reenable
    out, _err = capture_io { task.invoke(*args) }
    out
  end
end

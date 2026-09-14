class JournalEntriesController < DocumentsController
  def new
    super
    2.times { @document.journal_entry.lines.build }
  end

  private

  def documentable_class = JournalEntry
  def documentable_permitted
    [ :narrative, { lines_attributes: [ :id, :account_id, :debit_amount, :credit_amount, :memo, :_destroy, { tracking_option_ids: [] } ] } ]
  end
  def created_notice = "Journal entry posted."

  # Keep at least two blank rows on the form re-render.
  def after_failed_create
    lines = @document.journal_entry.lines
    (2 - lines.reject(&:marked_for_destruction?).size).times { lines.build }
  end
  alias_method :after_failed_update, :after_failed_create

  def load_form_collections
    @accounts = Plutus::Account.where(tenant: Current.organization).order(:type, :code, :name)
  end
end

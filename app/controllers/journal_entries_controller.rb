class JournalEntriesController < ApplicationController
  before_action :require_login
  before_action :load_accounts, only: %i[new create edit update]

  def index
    @journal_entries = Current.organization.journal_entries.order(posted_on: :desc, id: :desc)
  end

  def show
    @journal_entry = Current.organization.journal_entries.find(params[:id])
  end

  def new
    @journal_entry = Current.organization.journal_entries.build(posted_on: Date.current)
    2.times { @journal_entry.lines.build }
  end

  def create
    @journal_entry = Current.organization.journal_entries.build(journal_entry_params)
    if @journal_entry.save
      redirect_to journal_entry_path(@journal_entry), notice: "Journal entry posted."
    else
      # keep at least 2 blank rows on the form re-render
      (2 - @journal_entry.lines.reject(&:marked_for_destruction?).size).times { @journal_entry.lines.build }
      render :new, status: :unprocessable_entity
    end
  end

  private

  def load_accounts
    @accounts = Plutus::Account.where(tenant: Current.organization).order(:type, :code, :name)
  end

  def journal_entry_params
    params.require(:journal_entry).permit(
      :posted_on, :narrative, :reference,
      lines_attributes: %i[id account_id debit_amount credit_amount memo _destroy]
    )
  end
end

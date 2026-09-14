class TransfersController < DocumentsController
  private

  def documentable_class     = Transfer
  def documentable_permitted = %i[from_bank_account_id to_bank_account_id]
  def universal_permitted    = super + %i[total]
  def after_create_path      = transfers_path
  def created_notice         = "Transfer recorded."

  def load_form_collections
    @bank_accounts = Current.organization.bank_accounts.active.ordered
  end
end

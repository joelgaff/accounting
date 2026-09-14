# Shared by Bill and Expense: a vendor, expense-category line items, and the
# debit side of the posting (categories plus recoverable tax).
module PurchaseDocument
  extend ActiveSupport::Concern
  include Documentable

  included do
    before_validation :sync_vendor_from_contact
    validates :vendor, presence: true
  end

  def party_name = vendor

  def category_display
    names = document.line_items.filter_map { |li| li.account&.name }.uniq
    names.presence&.to_sentence || "Uncategorised"
  end

  private

  def sync_vendor_from_contact
    self.vendor = document.contact.name if document&.contact && vendor.blank?
  end

  # One debit per category account; recoverable tax debits the tax asset,
  # non-recoverable tax folds onto the first line's category (gross mode,
  # the way Xero and QBO record it).
  def purchase_debits(document)
    legs   = document.line_ledger_legs
    debits = legs[:accounts].map { |acct, amt| { account: acct, amount: amt } }
    legs[:taxes].each do |tax, amt|
      if tax.asset_account
        debits << { account: tax.asset_account, amount: amt }
      else
        debits.first[:amount] += amt
      end
    end
    debits
  end

  def first_category_name(document)
    document.line_items.first&.account&.name || "Uncategorised"
  end
end

class Invoice < ApplicationRecord
  belongs_to :organization
  belongs_to :contact,            optional: true
  belongs_to :receivable_account, class_name: "Plutus::Asset"
  belongs_to :revenue_account,    class_name: "Plutus::Revenue"
  has_many   :entries, class_name: "Plutus::Entry", as: :commercial_document

  before_validation :sync_client_name_from_contact
  validates :client_name, :amount, :due_date, presence: true
  validates :amount, numericality: { greater_than: 0 }

  after_create :post_to_ledger

  def customer_display = contact&.name.presence || client_name

  private

  def sync_client_name_from_contact
    self.client_name = contact.name if contact && client_name.blank?
  end

  def post_to_ledger
    Ledger.post(
      description: "Invoice ##{id} — #{client_name}",
      commercial_document: self,
      debits:  [{ account: receivable_account, amount: amount }],
      credits: [{ account: revenue_account,    amount: amount }]
    )
  end
end

class Invoice < ApplicationRecord
  belongs_to :organization
  belongs_to :receivable_account, class_name: "Plutus::Asset"
  belongs_to :revenue_account,    class_name: "Plutus::Revenue"
  has_many   :entries, class_name: "Plutus::Entry", as: :commercial_document

  validates :client_name, :amount, :due_date, presence: true
  validates :amount, numericality: { greater_than: 0 }

  after_create :post_to_ledger

  private

  def post_to_ledger
    Ledger.post(
      description: "Invoice ##{id} — #{client_name}",
      commercial_document: self,
      debits:  [{ account: receivable_account, amount: amount }],
      credits: [{ account: revenue_account,    amount: amount }]
    )
  end
end

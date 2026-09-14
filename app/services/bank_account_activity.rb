# Xero's "Account Transactions" tab for a bank account: every ledger movement
# on the bank's account, oldest first with a running balance, each row
# pointing at the document or payment behind it and saying whether a
# statement line has been reconciled against it.
class BankAccountActivity
  Row = Struct.new(:date, :entry, :record, :document, :kind, :party, :reference, :spent, :received, :balance, :reconciled, keyword_init: true) do
    def spent?    = spent.positive?
    def received? = received.positive?
  end

  def initialize(bank_account, from: nil, to: nil)
    @bank = bank_account
    @account = bank_account.account
    @from, @to = from, to
  end

  attr_reader :bank, :from, :to

  def rows
    @rows ||= begin
      running = opening_balance
      movements.map do |entry, debit, credit|
        received, spent = debit, credit   # money in debits the bank's account whatever its kind
        running += received - spent
        record   = entry.commercial_document
        document = record.is_a?(Payment) ? record.document : record
        Row.new(date: entry.date || entry.created_at.to_date, entry: entry, record: record, document: document,
                kind: kind_of(record), party: party_of(record, document), reference: document&.reference,
                spent: spent, received: received, balance: running, reconciled: reconciled?(record, document))
      end
    end
  end

  # Ledger balance before the window: money in less money out, so a credit
  # card reads as a negative number (what is owed), the way the bank shows it.
  def opening_balance
    return BigDecimal("0") unless from
    d = Plutus::DebitAmount.joins(:entry).where(account_id: @account.id, plutus_entries: { date: ...from }).sum(:amount)
    c = Plutus::CreditAmount.joins(:entry).where(account_id: @account.id, plutus_entries: { date: ...from }).sum(:amount)
    d - c
  end

  def closing_balance = rows.last&.balance || opening_balance
  def total_spent     = rows.sum(&:spent)
  def total_received  = rows.sum(&:received)
  def unreconciled    = rows.count { |r| r.reconciled == false }

  private

  # [entry, debit, credit] per entry touching the account, in date order.
  def movements
    amounts = Plutus::Amount.where(account_id: @account.id).joins(:entry).preload(entry: :commercial_document)
    amounts = amounts.where(plutus_entries: { date: from.. }) if from
    amounts = amounts.where(plutus_entries: { date: ..to })   if to
    amounts.group_by(&:entry).map do |entry, amts|
      [ entry,
        amts.select { |a| a.is_a?(Plutus::DebitAmount) }.sum(&:amount),
        amts.select { |a| a.is_a?(Plutus::CreditAmount) }.sum(&:amount) ]
    end.sort_by { |entry, _, _| [ entry.date || entry.created_at.to_date, entry.id ] }
  end

  # One word; the Spent and Received columns already say which way money went.
  def kind_of(record)
    case record
    when Payment  then "Payment"
    when Document then record.journal_entry? ? "Journal" : record.documentable.model_name.human
    else "Entry"
    end
  end

  def party_of(record, document)
    return record&.description.to_s unless document
    document.counterparty.presence || document.memo.to_s.truncate(60).presence || document.label
  end

  # Statement lines link to a payment or a document; a journal entry has
  # nothing to reconcile, so it stays nil rather than false.
  def reconciled?(record, document)
    case record
    when Payment  then record.bank_transaction_id.present?
    when Document then document.journal_entry? ? nil : linked_document_ids.include?(document.id)
    end
  end

  def linked_document_ids
    @linked_document_ids ||= bank.bank_transactions.where.not(document_id: nil).pluck(:document_id).to_set
  end
end

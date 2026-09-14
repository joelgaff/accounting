module Imports
  # Imports Xero's Journal Report — every posting in the general ledger since
  # the conversion date — as journal entries. This is what carries the history
  # the document importers can't: spend/receive money, transfers, manual
  # journals, conversion balances, credit notes, expense claims, payroll.
  #
  # Two shapes are accepted, keyed by the normalized headers:
  #
  #   API shape (Journals endpoint, one row per journal line):
  #     JournalDate, JournalNumber, SourceType, Reference, Description,
  #     AccountCode, AccountName, NetAmount [, TaxAmount, TaxType]
  #     NetAmount is signed: positive = debit, negative = credit.
  #
  #   Report shape (Accounting → Reports → Journal report → Export):
  #     Date, Journal number, Source, Reference, Description, Account code,
  #     Account, Debit, Credit
  #
  # Rows group by journal number; each group becomes one JournalEntry with a
  # line per row. Idempotent on the journal number: a re-import replaces the
  # entry and its ledger posting in place.
  #
  # Journals whose source is a sales invoice, a bill, or a payment on either
  # are skipped by default, because the invoice and bill importers already
  # post those with full document detail. Pass documents: :include to post
  # them too — the right choice when only the journal report is being loaded.
  class XeroJournalsService < BaseService
    ALIASES = {
      date:        %w[journaldate date],
      number:      %w[journalnumber journalno journal# journal journalid],
      source:      %w[sourcetype source type],
      reference:   %w[reference],
      description: %w[description narration details],
      code:        %w[accountcode code],
      name:        %w[accountname account],
      net:         %w[netamount amount],
      debit:       %w[debit],
      credit:      %w[credit]
    }.freeze

    # Source types the invoice and bill importers already cover.
    DOCUMENT_SOURCES = %w[
      ACCREC ACCPAY ACCRECPAYMENT ACCPAYPAYMENT
      ACCOUNTSRECEIVABLEINVOICE ACCOUNTSPAYABLEINVOICE SALESINVOICE PURCHASEINVOICE INVOICE BILL
      ACCOUNTSRECEIVABLEPAYMENT ACCOUNTSPAYABLEPAYMENT PAYMENTONINVOICE PAYMENTONBILL
      INVOICEPAYMENT BILLPAYMENT
    ].freeze

    SOURCE_LABELS = {
      "CASHPAID"       => "Spend money",
      "CASHREC"        => "Receive money",
      "TRANSFER"       => "Transfer",
      "MANJOURNAL"     => "Manual journal",
      "ACCRECCREDIT"   => "Credit note",
      "ACCPAYCREDIT"   => "Supplier credit note",
      "ARCREDITPAYMENT" => "Credit note refund",
      "APCREDITPAYMENT" => "Supplier credit refund",
      "ARPREPAYMENT"   => "Prepayment",
      "APPREPAYMENT"   => "Supplier prepayment",
      "AROVERPAYMENT"  => "Overpayment",
      "APOVERPAYMENT"  => "Supplier overpayment",
      "EXPCLAIM"       => "Expense claim",
      "EXPPAYMENT"     => "Expense claim payment",
      "PAYSLIP"        => "Payslip",
      "WAGEPAYABLE"    => "Wages payable",
      "EXTERNALSPENDMONEY" => "Spend money"
    }.freeze

    SQUEEZE = ->(s) { s.to_s.upcase.gsub(/[^A-Z0-9#]/, "") }

    def initialize(source, organization:, documents: :skip)
      @source       = source
      @organization = organization
      @documents    = documents
    end

    def call
      created = updated = skipped = 0
      errors  = []

      rows = self.class.csv(@source)
      return Result.new(errors: [ "CSV has no header row" ]) if rows.headers.compact.empty?

      cols = resolve_columns(rows.headers.compact)
      missing = %i[date number code].reject { |k| cols[k] }
      missing << :amount unless cols[:net] || (cols[:debit] && cols[:credit])
      if missing.any?
        return Result.new(errors: [ "Missing required columns: #{missing.map(&:to_s).join(", ")} " \
                                    "(need a date, a journal number, an account code, and NetAmount or Debit/Credit)" ])
      end

      accounts = AccountIndex.new(@organization)

      rows.group_by { |r| r[cols[:number]].to_s.strip }.each do |number, group|
        if number.blank?
          skipped += group.size
          errors << "journal number missing on #{group.size} row(s)"
          next
        end

        raw_source = cols[:source] ? group.first[cols[:source]].to_s.strip : ""
        source     = SQUEEZE.call(raw_source)
        if @documents == :skip && DOCUMENT_SOURCES.include?(source)
          skipped += 1
          next
        end

        begin
          ActiveRecord::Base.transaction(requires_new: true) do
            lines = build_lines(group, cols, accounts)
            raise Halt, "fewer than two non-zero lines" if lines.size < 2

            total = lines.sum { |l| l[:debit_amount] - l[:credit_amount] }
            raise Halt, "does not balance (off by #{'%.2f' % total})" unless total.abs < BigDecimal("0.005")

            existing = JournalEntry.joins(:document).where(documents: { organization_id: @organization.id })
                                   .find_by(xero_journal_number: number)&.document
            if existing
              Ledger.reset_for(existing)
              existing.destroy!
            end

            first = group.first
            @organization.documents.create!(
              date:      BaseService.parse_xero_date(first[cols[:date]]),
              reference: cols[:reference] ? first[cols[:reference]].to_s.strip.presence : nil,
              documentable: JournalEntry.new(
                narrative:           narrative_for(first, cols, source, raw_source, number),
                xero_journal_number: number,
                xero_source_type:    source.presence,
                lines_attributes:    lines
              )
            )
            existing ? updated += 1 : created += 1
          end
        rescue Halt => e
          skipped += 1
          errors << "journal #{number}: #{e.message}"
        rescue ActiveRecord::RecordInvalid => e
          skipped += 1
          errors << "journal #{number}: #{e.message}"
        end
      end

      Result.new(created: created, updated: updated, skipped: skipped, errors: errors)
    end

    private

    class Halt < StandardError; end

    # Ledger accounts by code and by name, loaded once.
    class AccountIndex
      def initialize(organization)
        scope    = organization.plutus_accounts
        @by_code = scope.where.not(code: nil).index_by(&:code)
        @by_name = scope.index_by { |a| a.name.to_s.strip.downcase }
      end

      def find(code:, name:)
        (code.present? && @by_code[code]) || (name.present? && @by_name[name.strip.downcase]) || nil
      end
    end

    def tracking = @tracking ||= TrackingResolver.new(@organization)

    def resolve_columns(headers)
      ALIASES.transform_values do |candidates|
        candidates.find { |c| headers.include?(c) } ||
          headers.find { |h| candidates.any? { |c| h.start_with?(c) && %w[debit credit].include?(c) } }
      end
    end

    def build_lines(group, cols, accounts)
      group.filter_map.with_index do |row, i|
        debit, credit = amounts_for(row, cols)
        next if debit.zero? && credit.zero?

        code = row[cols[:code]].to_s.strip.presence
        name = cols[:name] ? row[cols[:name]].to_s.strip.presence : nil
        account = accounts.find(code: code, name: name)
        raise Halt, "account #{(code || name).inspect} not in the Chart of Accounts" unless account

        {
          account_id:    account.id,
          debit_amount:  debit,
          credit_amount: credit,
          memo:          cols[:description] ? row[cols[:description]].to_s.strip.presence : nil,
          position:      i,
          tracking_option_ids: tracking.option_ids_for(row)
        }
      end
    end

    # [debit, credit] as non-negative decimals, from either shape.
    def amounts_for(row, cols)
      if cols[:debit] && cols[:credit]
        [ money(row[cols[:debit]]), money(row[cols[:credit]]) ]
      else
        net = money(row[cols[:net]], signed: true)
        net.positive? ? [ net, BigDecimal("0") ] : [ BigDecimal("0"), net.abs ]
      end
    end

    def money(value, signed: false)
      s = value.to_s.strip.delete(",$ ")
      return BigDecimal("0") if s.blank?
      s = "-#{s[1..-2]}" if s.start_with?("(") && s.end_with?(")")
      d = BigDecimal(s)
      signed ? d : d.abs
    rescue ArgumentError
      raise Halt, "unreadable amount #{value.inspect}"
    end

    def narrative_for(row, cols, source, raw_source, number)
      desc = cols[:description] ? row[cols[:description]].to_s.strip.presence : nil
      ref  = cols[:reference]   ? row[cols[:reference]].to_s.strip.presence   : nil
      label = SOURCE_LABELS[source] || raw_source.presence || "Xero journal"
      [ label, desc || ref || "##{number}" ].join(": ")
    end
  end
end

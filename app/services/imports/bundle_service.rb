require "yaml"

module Imports
  # Runs a directory of Xero-format CSVs through the importers in dependency
  # order, so the same bundle produces the same books in any environment.
  # Nothing about the books lives in code: accounts, contacts, documents and
  # which accounts Settings should point at all come from the bundle.
  #
  #   bundle/
  #     chart_of_accounts.csv    required — Xero's Chart of Accounts export
  #     settings.yml             optional — receivable_account / payable_account /
  #                                         bank_account, each a code or a name
  #     contacts_customers.csv   optional — Xero contacts export, imported as customers
  #     contacts_vendors.csv     optional — Xero contacts export, imported as vendors
  #     invoices.csv             optional — Xero sales invoices export (+ AmountPaid,
  #                                         FullyPaidOnDate, BankAccount if you have them)
  #     bills.csv                optional — Xero bills export, same extras
  #
  # Every importer is idempotent, so re-running a bundle corrects rather than
  # duplicates. With dry_run: true the whole run happens inside a transaction
  # that is rolled back at the end, and the report shows what would have happened.
  class BundleService
    Step   = Struct.new(:name, :result, keyword_init: true)
    Report = Struct.new(:steps, :summary, :dry_run, :fatal, keyword_init: true) do
      def failed? = fatal.present? || steps.any? { |s| s.result.errors.any? }

      def to_s
        lines = []
        lines << "DRY RUN — nothing was written" if dry_run
        steps.each do |s|
          r = s.result
          lines << format("%-22s created=%-4d updated=%-4d skipped=%-4d", s.name, r.created, r.updated, r.skipped)
          r.errors.each { |e| lines << "    ! #{e}" }
        end
        lines << "FAILED: #{fatal}" if fatal
        if summary
          lines << ""
          summary.each { |k, v| lines << format("  %-24s %s", k, v) }
        end
        lines.join("\n")
      end
    end

    SETTINGS_KEYS = {
      "receivable_account" => Plutus::Asset,
      "payable_account"    => Plutus::Liability,
      "bank_account"       => BankAccount
    }.freeze

    class Fatal < StandardError; end

    def initialize(dir, organization:, dry_run: false)
      @dir          = Pathname.new(dir)
      @organization = organization
      @dry_run      = dry_run
    end

    def call
      steps = []
      fatal = nil

      ActiveRecord::Base.transaction do
        steps << step("chart of accounts", ChartOfAccountsImportService.new(read!("chart_of_accounts.csv"), organization: @organization))
        raise Fatal, "chart of accounts had errors — nothing else can post until it is clean" if steps.last.result.errors.any?

        apply_settings!

        if exists?("contacts_customers.csv")
          steps << step("contacts (customers)", ContactsImportService.new(read!("contacts_customers.csv"), organization: @organization, default_kind: "customer"))
        end
        if exists?("contacts_vendors.csv")
          steps << step("contacts (vendors)", ContactsImportService.new(read!("contacts_vendors.csv"), organization: @organization, default_kind: "vendor"))
        end
        if exists?("invoices.csv")
          steps << step("sales invoices", Imports::XeroInvoicesService.new(read!("invoices.csv"), organization: @organization))
        end
        if exists?("bills.csv")
          steps << step("bills", Imports::XeroBillsService.new(read!("bills.csv"), organization: @organization))
        end

        @summary = summarize
        raise ActiveRecord::Rollback if @dry_run
      rescue Fatal => e
        fatal = e.message
        raise ActiveRecord::Rollback
      end

      Report.new(steps: steps, summary: @summary, dry_run: @dry_run, fatal: fatal)
    end

    private

    def step(name, service)
      Step.new(name: name, result: service.call)
    end

    def exists?(file) = @dir.join(file).file?

    def read!(file)
      path = @dir.join(file)
      raise Fatal, "#{file} not found in #{@dir}" unless path.file?
      path.read
    end

    # settings.yml names the accounts by code or by name; either must already be
    # in the chart of accounts imported a moment ago.
    def apply_settings!
      return unless exists?("settings.yml")

      wanted   = YAML.safe_load(read!("settings.yml")) || {}
      unknown  = wanted.keys - SETTINGS_KEYS.keys
      raise Fatal, "settings.yml has unknown keys: #{unknown.join(', ')}" if unknown.any?

      settings = @organization.settings || @organization.create_settings!
      attrs = wanted.to_h do |key, ref|
        klass   = SETTINGS_KEYS.fetch(key)
        account = if klass == BankAccount
          @organization.bank_accounts.find_by_code_or_name(ref.to_s)
        else
          scope = klass.where(tenant_id: @organization.id)
          scope.find_by(code: ref.to_s) || scope.find_by(name: ref.to_s)
        end
        raise Fatal, "settings.yml: no #{klass.name.demodulize.underscore.humanize.downcase} matching #{ref.inspect} for #{key}" unless account
        [ key, account ]
      end
      settings.update!(attrs)
    end

    def summarize
      s      = @organization.settings
      debits  = Plutus::DebitAmount.sum(:amount)
      credits = Plutus::CreditAmount.sum(:amount)
      {
        "accounts"       => @organization.plutus_accounts.count,
        "contacts"       => @organization.contacts.count,
        "invoices"       => @organization.invoices.count,
        "bills"          => @organization.expenses.count,
        "payments"       => Payment.where(organization: @organization).count,
        "trial balance"  => format("debits %.2f  credits %.2f  %s", debits, credits, debits == credits ? "BALANCED" : "OUT OF BALANCE"),
        "receivable"     => balance_line(s&.receivable_account),
        "payable"        => balance_line(s&.payable_account),
        "bank"           => balance_line(s&.bank_account)
      }
    end

    def balance_line(account)
      return "(not set)" unless account
      format("%s  %.2f", account.name, account.balance)
    end
  end
end

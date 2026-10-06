module Xero
  # The whole migration from the API, in the same order a bundle runs: the
  # chart, tax rates, contacts, tracking categories, sales invoices, bills,
  # then every other journal. Each step records its result on the connection
  # so the Settings page can show progress while the job runs.
  class Import
    def initialize(connection, client: connection.client, from: connection.import_from)
      @connection = connection
      @client     = client
      @pull       = Pull.new(client)
      @org        = connection.organization
      @from       = from
    end

    def call
      @connection.update!(status: "running", started_at: Time.current, progress: "[]", last_error: nil)
      Current.organization = @org

      step("chart of accounts") { ChartOfAccountsImportService.new(@pull.chart_csv, organization: @org).call }
      align_bank_kinds!
      point_settings!
      step("tax rates")        { Imports::TaxRatesService.new(@pull.tax_rates_csv, organization: @org).call }
      customers, vendors, both = @pull.contacts_csvs
      step("contacts (customers)") { ContactsImportService.new(customers, organization: @org, default_kind: "customer").call }
      step("contacts (vendors)")   { ContactsImportService.new(vendors,   organization: @org, default_kind: "vendor").call }
      step("contacts (both)")      { ContactsImportService.new(both,      organization: @org, default_kind: "both").call }
      step("tracking categories")  { seed_tracking! }
      step("sales invoices")   { Imports::XeroInvoicesService.new(@pull.invoices_csv("ACCREC", from: @from), organization: @org).call }
      step("bills")            { Imports::XeroBillsService.new(@pull.invoices_csv("ACCPAY", from: @from), organization: @org).call }
      step("journals")         { Imports::XeroJournalsService.new(@pull.journals_csv(from: @from), organization: @org, documents: :skip).call }

      @connection.update!(status: "done", last_import_at: Time.current, last_summary: Imports::BooksSummary.new(@org).to_h.to_json)
      @connection
    rescue => e
      @connection.update!(status: "failed", last_error: "#{e.class}: #{e.message}".truncate(500))
      raise
    ensure
      Current.reset
    end

    private

    def step(name)
      @connection.record_step!(name)
      result = yield
      @connection.record_step!(name, result)
      result
    end

    # Xero knows which bank accounts are cards; the chart importer only guesses.
    def align_bank_kinds!
      @pull.accounts.select { |a| a["Type"] == "BANK" }.each do |a|
        bank = @org.bank_accounts.find_by_code_or_name(a["Code"].presence || a["Name"]) or next
        wanted = a["BankAccountType"] == "CREDITCARD" ? "credit_card" : BankAccount.guess_kind(a["Name"])
        bank.update!(kind: wanted) if bank.kind != wanted
      end
    end

    # Xero marks its receivable and payable control accounts; Settings needs them.
    def point_settings!
      settings = @org.settings
      debtors   = @pull.accounts.find { |a| a["SystemAccount"] == "DEBTORS" }
      creditors = @pull.accounts.find { |a| a["SystemAccount"] == "CREDITORS" }
      settings.receivable_account ||= Plutus::Asset.where(tenant: @org).find_by(code: debtors["Code"])       if debtors
      settings.payable_account    ||= Plutus::Liability.where(tenant: @org).find_by(code: creditors["Code"]) if creditors
      settings.bank_account       ||= @org.bank_accounts.active.ordered.first
      settings.save!
    end

    # Categories and options exactly as Xero has them; the first two active
    # ones stay active here too, since the sheets show at most two.
    def seed_tracking!
      created = updated = 0
      active_left = TrackingCategory::MAX_ACTIVE - @org.tracking_categories.active.count
      @pull.tracking_categories.each do |cat|
        category = @org.tracking_categories.find_by("LOWER(name) = ?", cat["Name"].to_s.downcase)
        if category
          updated += 1
        else
          active = cat["Status"] == "ACTIVE" && active_left.positive?
          active_left -= 1 if active
          category = @org.tracking_categories.create!(name: cat["Name"], active: active, position: (@org.tracking_categories.maximum(:position) || 0) + 1)
          created += 1
        end
        Array(cat["Options"]).each_with_index do |opt, i|
          next if category.options.exists?([ "LOWER(name) = ?", opt["Name"].to_s.downcase ])
          category.options.create!(name: opt["Name"], active: opt["Status"] != "ARCHIVED", position: i + 1)
        end
      end
      Imports::BaseService::Result.new(created: created, updated: updated)
    end
  end
end

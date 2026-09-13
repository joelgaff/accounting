module Imports
  # Seeds tax rates from a CSV with Name, TaxType and Rate columns — the
  # shape of Xero's TaxRates API, or a hand-rolled file. Rate may be a
  # percentage (10, 10%) or a fraction (0.10). Idempotent on the name.
  #
  # OUTPUT rates (tax collected on sales) get the liability account named in
  # LiabilityAccount; INPUT rates (recoverable purchase tax) get the asset in
  # AssetAccount. Both optional, each a code or a name from the chart.
  class TaxRatesService < BaseService
    REQUIRED = %w[name rate].freeze

    def initialize(source, organization:)
      @source       = source
      @organization = organization
    end

    def call
      created = updated = skipped = 0
      errors  = []

      rows    = self.class.csv(@source)
      missing = REQUIRED - rows.headers.compact
      return Result.new(errors: [ "Missing required columns: #{missing.join(", ")}" ]) if missing.any?

      rows.each.with_index(2) do |row, line|
        name = row["name"].to_s.strip
        if name.blank?
          skipped += 1
          errors << "row #{line}: name is required"
          next
        end

        begin
          rate = parse_rate(row["rate"])
          tax  = @organization.tax_rates.find_or_initialize_by(name: name)
          tax.rate              = rate
          tax.xero_tax_type     = row["taxtype"].to_s.strip.presence
          tax.liability_account = resolve(Plutus::Liability, row["liabilityaccount"]) if row.headers.include?("liabilityaccount")
          tax.asset_account     = resolve(Plutus::Asset,     row["assetaccount"])     if row.headers.include?("assetaccount")
          was_new = tax.new_record?
          tax.save!
          was_new ? created += 1 : updated += 1
        rescue ArgumentError, ActiveRecord::RecordInvalid => e
          skipped += 1
          errors << "row #{line}: #{e.message}"
        end
      end

      Result.new(created: created, updated: updated, skipped: skipped, errors: errors)
    end

    private

    def parse_rate(raw)
      s = raw.to_s.strip
      raise ArgumentError, "rate is required" if s.blank?
      percent = s.end_with?("%")
      d = BigDecimal(s.delete("%"))
      d = d / 100 if percent || d >= 1
      d
    rescue ArgumentError
      raise ArgumentError, "unreadable rate #{raw.inspect}"
    end

    def resolve(klass, ref)
      key = ref.to_s.strip
      return nil if key.blank?
      scope = klass.where(tenant: @organization)
      scope.find_by(code: key) || scope.find_by(name: key) ||
        raise(ArgumentError, "no #{klass.name.demodulize.downcase} account matching #{key.inspect}")
    end
  end
end

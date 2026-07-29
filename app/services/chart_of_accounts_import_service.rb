class ChartOfAccountsImportService < Imports::BaseService
  # Xero's *Type values → plutus STI class
  XERO_TYPE_MAP = {
    # Assets
    "BANK"            => Plutus::Asset,
    "CURRENT"         => Plutus::Asset,
    "FIXED"           => Plutus::Asset,
    "INVENTORY"       => Plutus::Asset,
    "PREPAYMENT"      => Plutus::Asset,
    "NONCURRENT"      => Plutus::Asset,
    "ASSET"           => Plutus::Asset,
    # Liabilities
    "CURRLIAB"        => Plutus::Liability,
    "LIABILITY"       => Plutus::Liability,
    "TERMLIAB"        => Plutus::Liability,
    "NONCURRLIAB"     => Plutus::Liability,
    "PAYGLIABILITY"   => Plutus::Liability,
    # Equity
    "EQUITY"          => Plutus::Equity,
    "RETAINEDEARNINGS"=> Plutus::Equity,
    "HISTORICAL"      => Plutus::Equity,
    # Revenue
    "REVENUE"         => Plutus::Revenue,
    "SALES"           => Plutus::Revenue,
    "OTHERINCOME"     => Plutus::Revenue,
    # Expense
    "EXPENSE"         => Plutus::Expense,
    "DIRECTCOSTS"     => Plutus::Expense,
    "OVERHEADS"       => Plutus::Expense,
    "DEPRECIATN"      => Plutus::Expense
  }.freeze

  # Plain-English fallback (e.g. hand-rolled CSV without Xero codes)
  PLAIN_TYPE_MAP = {
    "asset"     => Plutus::Asset,
    "liability" => Plutus::Liability,
    "equity"    => Plutus::Equity,
    "revenue"   => Plutus::Revenue,
    "income"    => Plutus::Revenue,
    "expense"   => Plutus::Expense
  }.freeze

  def initialize(source, organization:)
    @source       = source
    @organization = organization
  end

  def call
    created = updated = skipped = 0
    errors  = []

    rows = self.class.csv(@source)

    if rows.headers.compact.empty?
      return Result.new(errors: ["CSV has no header row"])
    end

    unless rows.headers.include?("name") && rows.headers.include?("type")
      return Result.new(errors: ["CSV must have at least Name and Type columns (Code, Description optional)"])
    end

    ActiveRecord::Base.transaction do
      rows.each.with_index(2) do |row, line|
        begin
          name = row["name"].to_s.strip
          type = row["type"].to_s.strip
          code = row["code"]&.to_s&.strip.presence
          desc = row["description"]&.to_s&.strip.presence

          if name.blank? || type.blank?
            skipped += 1
            errors << "row #{line}: name and type are required"
            next
          end

          klass = classify(type)
          unless klass
            skipped += 1
            errors << "row #{line}: unrecognized account type #{type.inspect}"
            next
          end

          account = find_existing(code: code, name: name)

          if account
            if account.type != klass.name
              skipped += 1
              errors << "row #{line}: refusing to change #{account.name.inspect} from #{account.type.demodulize} to #{klass.name.demodulize}"
              next
            end
            account.update!(name: name, code: code, description: desc, xero_type: type.upcase)
            updated += 1
          else
            klass.create!(tenant: @organization, name: name, code: code, description: desc, xero_type: type.upcase)
            created += 1
          end
        rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
          skipped += 1
          errors << "row #{line}: #{e.message}"
        end
      end
    end

    Result.new(created: created, updated: updated, skipped: skipped, errors: errors)
  end

  private

  def classify(raw)
    key = raw.strip
    XERO_TYPE_MAP[key.upcase] || PLAIN_TYPE_MAP[key.downcase]
  end

  def find_existing(code:, name:)
    scope = Plutus::Account.where(tenant: @organization)
    (code && scope.find_by(code: code)) || scope.find_by(name: name)
  end
end

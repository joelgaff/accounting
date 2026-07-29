require "csv"

module Imports
  # Shared plumbing for all CSV importers.
  #
  # Subclasses implement #call and use the helpers below:
  #   - Result — value struct every importer returns
  #   - .csv(source, headers: true) — normalized CSV::Table
  #   - #parse_xero_date — ISO-8601 or Xero's `DD MMM YYYY`
  #
  # Header normalization strips a leading `*`, lowercases, and removes
  # whitespace so Xero's `*ContactName` and a hand-rolled `contact name`
  # both land as `contactname`.
  class BaseService
    Result = Struct.new(:created, :updated, :skipped, :errors, :duplicates, keyword_init: true) do
      def initialize(created: 0, updated: 0, skipped: 0, errors: [], duplicates: 0)
        super
      end
    end

    HEADER_CONVERTER = ->(h) { h.to_s.sub(/\A\*/, "").strip.downcase.gsub(/\s+/, "") }

    def self.csv(source)
      data = source.respond_to?(:read) ? source.read : source
      CSV.parse(data, headers: true, header_converters: HEADER_CONVERTER)
    end

    def self.parse_xero_date(value)
      return nil if value.blank?
      s = value.to_s.strip
      Date.parse(s)
    rescue ArgumentError
      begin
        Date.strptime(s, "%d %b %Y")
      rescue ArgumentError
        Date.strptime(s, "%d/%m/%Y")
      end
    end
  end
end

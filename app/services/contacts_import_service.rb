require "csv"

# Imports Xero's "Contacts CSV" (Business → Contacts → Export).
# The export has one row per contact with header columns like:
#   *ContactName, EmailAddress, FirstName, LastName, POAttentionTo,
#   POAddressLine1..4, POCity, PORegion, POPostalCode, POCountry,
#   PhoneNumber, MobileNumber, DDIPhoneNumber, FaxNumber, SkypeName,
#   AccountNumber, TaxNumber, BankAccountName, BankAccountNumber, ...
#
# We use *ContactName as the unique key. Kind defaults to "both" since
# Xero exports doesn't tell us which contacts are customers vs vendors;
# the user can retype later, or import separate Customers / Suppliers
# exports and pass `default_kind:` accordingly.
class ContactsImportService
  Result = Struct.new(:created, :updated, :skipped, :errors, keyword_init: true)

  def initialize(source, organization:, default_kind: "both")
    @source       = source
    @organization = organization
    @default_kind = default_kind
  end

  def call
    created = updated = skipped = 0
    errors = []

    data = @source.respond_to?(:read) ? @source.read : @source
    rows = CSV.parse(data, headers: true, header_converters: ->(h) { normalize_header(h) })

    unless rows.headers.include?("contactname")
      return Result.new(created: 0, updated: 0, skipped: 0,
                        errors: ["CSV must have a ContactName column (Xero exports it as *ContactName)"])
    end

    ActiveRecord::Base.transaction do
      rows.each.with_index(2) do |row, line|
        begin
          name = row["contactname"].to_s.strip
          if name.blank?
            skipped += 1
            errors << "row #{line}: ContactName is required"
            next
          end

          contact = @organization.contacts.find_or_initialize_by(name: name)
          attrs = {
            kind:           contact.new_record? ? @default_kind : contact.kind,
            email:          row["emailaddress"].presence,
            first_name:     row["firstname"].presence,
            last_name:      row["lastname"].presence,
            phone:          (row["phonenumber"].presence || row["mobilenumber"].presence),
            tax_number:     row["taxnumber"].presence,
            company_number: row["accountnumber"].presence,
            address:        compose_address(row),
            city:           row["pocity"].presence,
            region:         row["poregion"].presence,
            postal_code:    row["popostalcode"].presence,
            country:        row["pocountry"].presence
          }.compact
          was_new = contact.new_record?
          contact.assign_attributes(attrs)
          contact.save!
          was_new ? created += 1 : updated += 1
        rescue ActiveRecord::RecordInvalid => e
          skipped += 1
          errors << "row #{line}: #{e.message}"
        end
      end
    end

    Result.new(created: created, updated: updated, skipped: skipped, errors: errors)
  end

  private

  def normalize_header(h)
    h.to_s.sub(/\A\*/, "").strip.downcase.gsub(/\s+/, "")
  end

  def compose_address(row)
    lines = (1..4).map { |n| row["poaddressline#{n}"].to_s.strip }.reject(&:blank?)
    lines.join("\n").presence
  end
end

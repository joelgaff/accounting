# Ids arrive from forms. Every reference a record takes must belong to the
# same organisation as the record, whether the target carries
# organization_id (ours) or tenant_id (the ledger's accounts).
#
#   scoped_to_organization :account, :tax_rate, organization: ->(line) { line.lineable&.organization }
module OrganizationScoped
  extend ActiveSupport::Concern

  class_methods do
    def scoped_to_organization(*associations, organization:)
      validate do
        org = organization.call(self)
        next if org.nil?
        associations.each do |name|
          target = public_send(name)
          next if target.nil?
          other = target.respond_to?(:organization_id) ? target.organization_id : target.tenant_id
          errors.add(name, "must belong to this organization") unless other.nil? || other == org.id
        end
      end
    end
  end
end

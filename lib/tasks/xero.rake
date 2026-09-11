namespace :xero do
  desc "Import a bundle of Xero-format CSVs into the books (see Imports::BundleService). DRY_RUN=1 rolls back; ORG_ID picks the organisation."
  task :import, [ :dir ] => :environment do |_, args|
    dir = args[:dir].presence or abort "usage: bin/rails 'xero:import[/path/to/bundle]'   (DRY_RUN=1 to roll back, ORG_ID=n to pick an org)"

    org = ENV["ORG_ID"].present? ? Organization.find(ENV["ORG_ID"]) : Organization.sole
    Current.organization = org

    report = Imports::BundleService.new(dir, organization: org, dry_run: ENV["DRY_RUN"].present?).call
    puts "Importing #{dir} into #{org.name} (#{Rails.env})"
    puts report
    abort "import finished with errors" if report.failed?
  end
end

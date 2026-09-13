ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # A bank account plus its ledger account in one line, the way the form makes them.
    def create_bank_account(org, name:, code: nil, kind: "checking")
      BankAccount.create!(organization: org, name: name, code: code, kind: kind)
    end
  end
end

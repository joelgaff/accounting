ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module DocumentBuilders
  # One-line documents for tests: a single line item per document, tax on top.
  def create_invoice(org, amount:, receivable:, revenue:, client_name: nil, due_date: Date.current + 30,
                     date: Date.current, tax_rate: nil, contact: nil, **doc)
    org.documents.create!(doc.merge(
      contact: contact, date: date,
      documentable: Invoice.new(client_name: client_name, due_date: due_date, receivable_account: receivable),
      line_items_attributes: [ { description: "Services rendered", quantity: 1, unit_amount: amount,
                                 account_id: revenue.id, tax_rate_id: tax_rate&.id } ]
    ))
  end

  def create_bill(org, amount:, category:, payable:, vendor: nil, date: Date.current, tax_rate: nil, contact: nil, **doc)
    org.documents.create!(doc.merge(
      contact: contact, date: date,
      documentable: Bill.new(vendor: vendor, payable_account: payable),
      line_items_attributes: [ { description: "Bill line", quantity: 1, unit_amount: amount,
                                 account_id: category.id, tax_rate_id: tax_rate&.id } ]
    ))
  end

  def create_expense(org, amount:, category:, bank_account:, vendor: nil, date: Date.current, tax_rate: nil, contact: nil, **doc)
    org.documents.create!(doc.merge(
      contact: contact, date: date,
      documentable: Expense.new(vendor: vendor, bank_account: bank_account),
      line_items_attributes: [ { description: "Expense line", quantity: 1, unit_amount: amount,
                                 account_id: category.id, tax_rate_id: tax_rate&.id } ]
    ))
  end

  def create_bank_account(org, name:, code: nil, kind: "checking")
    BankAccount.create!(organization: org, name: name, code: code, kind: kind)
  end
end

module LaunchpadSession
  # Forge the Launchpad JWT cookie for the app's single organisation.
  def sign_in_as_launchpad_user(org, email: "joel@example.com", name: "Joel")
    Organization.where.not(id: org.id).destroy_all   # set_organization resolves Organization.first
    payload = { sub: "u-#{org.id}", email: email, name: name, apps: [ "accounting" ],
                iat: Time.current.to_i, exp: 1.hour.from_now.to_i, iss: Ee::Jwt::ISSUER }
    cookies[Ee::Jwt::COOKIE_NAME.to_s] = ::JWT.encode(payload, Rails.application.credentials.ee_jwt_secret, "HS256")
  end
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    include DocumentBuilders
  end
end

class ActionDispatch::IntegrationTest
  include LaunchpadSession
end

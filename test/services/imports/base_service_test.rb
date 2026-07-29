require "test_helper"

class Imports::BaseServiceTest < ActiveSupport::TestCase
  test "csv normalizes headers: strip *, downcase, remove whitespace" do
    csv = Imports::BaseService.csv("*Contact Name,EmailAddress\nAcme,x@y.com\n")
    assert_equal ["contactname", "emailaddress"], csv.headers
    assert_equal "Acme", csv.first["contactname"]
  end

  test "parse_xero_date handles ISO-8601 and DD MMM YYYY and DD/MM/YYYY" do
    assert_equal Date.new(2026, 7, 28), Imports::BaseService.parse_xero_date("2026-07-28")
    assert_equal Date.new(2026, 7, 28), Imports::BaseService.parse_xero_date("28 Jul 2026")
    assert_equal Date.new(2026, 7, 28), Imports::BaseService.parse_xero_date("28/07/2026")
    assert_nil Imports::BaseService.parse_xero_date("")
    assert_nil Imports::BaseService.parse_xero_date(nil)
  end

  test "Result defaults are safe (no keyword args required)" do
    r = Imports::BaseService::Result.new
    assert_equal 0, r.created
    assert_equal 0, r.updated
    assert_equal 0, r.skipped
    assert_equal 0, r.duplicates
    assert_equal [], r.errors
  end
end

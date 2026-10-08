require "test_helper"

class ContactsSearchTest < ActionDispatch::IntegrationTest
  setup do
    @org = organizations(:one)
    sign_in_as_launchpad_user(@org)
    @northwind = @org.contacts.create!(name: "Northwind Trail Series", kind: "customer", email: "ops@northwind.example")
    @gusto     = @org.contacts.create!(name: "Gusto", kind: "vendor", email: "billing@gusto.example", phone: "555-0100")
    @zoom      = @org.contacts.create!(name: "Zoom", kind: "vendor")
  end

  def row(contact) = "tr##{ActionView::RecordIdentifier.dom_id(contact)}"

  test "the contacts page searches name, email and phone, inside a frame the search box drives" do
    get contacts_path
    assert_select "form[data-controller=search] input[name=q][data-action*='search#']"
    assert_select "turbo-frame##{ActionView::RecordIdentifier.dom_id(@org, :contacts)} #{row(@northwind)}"

    get contacts_path(q: "north")
    assert_select row(@northwind), 1
    assert_select row(@gusto), 0
    get contacts_path(q: "gusto.example")
    assert_select row(@gusto), 1
    get contacts_path(q: "0100")
    assert_select row(@gusto), 1
    assert_select row(@zoom), 0

    get contacts_path(q: "o", kind: "vendor")
    assert_select row(@gusto), 1
    assert_select row(@zoom), 1
    assert_select row(@northwind), 0, "the kind chips still narrow a search"
    assert_select "nav.chips a[aria-current=page][href*='q=o']", text: "Vendors"

    get contacts_path(q: "%")
    assert_select "tbody tr", 0, "a wildcard is just a character nobody is named"
    assert_select ".empty-state", text: /Nothing matches “%”/
    assert_select ".empty-state", text: /No contacts yet/, count: 0
  end
end

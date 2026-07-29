require "test_helper"

class InvoiceMailerTest < ActionMailer::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    ar    = Plutus::Asset.create!(tenant: @org, name: "AR")
    sales = Plutus::Revenue.create!(tenant: @org, name: "Sales")
    @invoice = @org.invoices.create!(client_name: "Acme", amount: 500, due_date: Date.current + 30,
                                     receivable_account: ar, revenue_account: sales)
  end

  test "renders default subject and address" do
    mail = InvoiceMailer.send_invoice(@invoice, to: "billing@acme.example")
    assert_equal ["billing@acme.example"], mail.to
    assert_match(/Invoice ##{@invoice.id}/, mail.subject)
    assert_match(/500\.00/, mail.body.encoded)
    assert_match(/Acme/, mail.body.encoded)
  end

  test "custom subject and body are honored" do
    mail = InvoiceMailer.send_invoice(@invoice, to: "x@y.com", subject: "Please pay", body: "Cheers!")
    assert_equal "Please pay", mail.subject
    assert_match(/Cheers!/, mail.body.encoded)
  end
end

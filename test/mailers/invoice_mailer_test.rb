require "test_helper"

class InvoiceMailerTest < ActionMailer::TestCase
  setup do
    @org = organizations(:one)
    Current.organization = @org
    ar    = Plutus::Asset.create!(tenant: @org, name: "AR")
    sales = Plutus::Revenue.create!(tenant: @org, name: "Sales")
    @invoice = create_invoice(@org, client_name: "Acme", amount: 500, receivable: ar, revenue: sales)
  end

  test "renders default subject and address, with the invoice PDF attached" do
    mail = InvoiceMailer.send_invoice(@invoice, to: "billing@acme.example")
    assert_equal [ "billing@acme.example" ], mail.to
    assert_match(/Invoice ##{@invoice.id}/, mail.subject)
    assert_match(/500\.00/, mail.body.encoded)
    assert_match(/Acme/, mail.body.encoded)
    pdf = mail.attachments["invoice-#{@invoice.id}.pdf"]
    assert pdf, "PDF attached"
    assert_equal "application/pdf", pdf.mime_type
    assert pdf.body.decoded.start_with?("%PDF-")
  end

  test "custom subject and body are honored" do
    mail = InvoiceMailer.send_invoice(@invoice, to: "x@y.com", subject: "Please pay", body: "Cheers!")
    assert_equal "Please pay", mail.subject
    assert_match(/Cheers!/, mail.body.encoded)
  end
end

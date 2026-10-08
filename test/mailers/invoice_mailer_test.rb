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
    assert_match(/Invoice #{@invoice.invoice.number}/, mail.subject)
    assert_match(/500\.00/, mail.body.encoded)
    assert_match(/Acme/, mail.body.encoded)
    pdf = mail.attachments["invoice-#{@invoice.invoice.number.downcase}.pdf"]
    assert pdf, "PDF attached"
    assert_equal "application/pdf", pdf.mime_type
    assert pdf.body.decoded.start_with?("%PDF-")
  end

  test "refuses to build a mail for a draft" do
    @invoice.unapprove!
    assert_raises(InvoiceMailer::DraftError) { InvoiceMailer.send_invoice(@invoice, to: "billing@acme.example").message }
  end

  test "mail goes out in the organisation's name, with replies where Settings says" do
    mail = InvoiceMailer.send_invoice(@invoice, to: "billing@acme.example")
    assert_equal @org.name, mail[:from].display_names.first, "the entity, not the software, until a name is set"
    assert_nil mail.reply_to

    @org.settings.update!(email_from_name: "EE Timing Billing", email_reply_to: "joel@enduranceevolution.example")
    mail = InvoiceMailer.send_invoice(@invoice.reload, to: "billing@acme.example")
    assert_equal "EE Timing Billing", mail[:from].display_names.first
    assert_equal [ "joel@enduranceevolution.example" ], mail.reply_to
    assert_equal [ ApplicationMailer.sending_address ], mail.from, "the address itself is the operator's"
  end

  test "custom subject and body are honored" do
    mail = InvoiceMailer.send_invoice(@invoice, to: "x@y.com", subject: "Please pay", body: "Cheers!")
    assert_equal "Please pay", mail.subject
    assert_match(/Cheers!/, mail.body.encoded)
  end
end

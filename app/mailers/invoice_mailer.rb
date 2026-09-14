class InvoiceMailer < ApplicationMailer
  def send_invoice(invoice, to:, subject: nil, body: nil)
    @invoice = invoice
    @body    = body
    attachments[InvoicePdf.filename(invoice)] = { mime_type: "application/pdf", content: InvoicePdf.new(invoice).render }
    mail to: to, subject: subject.presence || self.class.default_subject(invoice)
  end

  def self.default_subject(invoice)
    "Invoice ##{invoice.id} from #{invoice.organization.name} — $#{'%.2f' % invoice.total}"
  end
end

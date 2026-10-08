class InvoiceMailer < ApplicationMailer
  class DraftError < StandardError; end

  def send_invoice(invoice, to:, subject: nil, body: nil)
    raise DraftError, "#{invoice.label} is a draft and can't be sent" if invoice.draft?
    @invoice = invoice
    @body    = body
    attachments[InvoicePdf.filename(invoice)] = { mime_type: "application/pdf", content: InvoicePdf.new(invoice).render }
    mail to: to, subject: subject.presence || self.class.default_subject(invoice), **sender_for(invoice.organization)
  end

  def self.default_subject(invoice)
    "Invoice #{invoice.invoice.number} from #{invoice.organization.name} — $#{'%.2f' % invoice.total}"
  end
end

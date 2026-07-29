class InvoiceMailer < ApplicationMailer
  def send_invoice(invoice, to:, subject: nil, body: nil)
    @invoice = invoice
    @body    = body
    mail to: to, subject: subject.presence || default_subject(invoice)
  end

  private

  def default_subject(invoice)
    "Invoice ##{invoice.id} from #{invoice.organization.name} — $#{'%.2f' % invoice.amount}"
  end
end

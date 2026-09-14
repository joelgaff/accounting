require "prawn"
require "prawn/table"

# The invoice as a PDF, laid out like the print page: header, billed-to and
# balance, lines, totals. Pure Ruby (Prawn), so it runs anywhere the app does.
class InvoicePdf
  FONT_DIR = Rails.root.join("vendor/fonts")
  INK, DIM, RULE = "14181F", "5D6672", "D8DDE4"

  def self.filename(document) = "invoice-#{document.id}.pdf"

  def initialize(document)
    @document = document
    @invoice  = document.invoice
    @org      = document.organization
  end

  def render
    Prawn::Document.new(page_size: "LETTER", margin: 54, info: { Title: "Invoice ##{@document.id}", Author: @org.name, Creator: @org.name }) do |pdf|
      pdf.font_families.update("Body" => { normal: FONT_DIR.join("LiberationSans-Regular.ttf").to_s, bold: FONT_DIR.join("LiberationSans-Bold.ttf").to_s })
      pdf.font "Body"
      pdf.fill_color INK
      header(pdf)
      parties(pdf)
      lines(pdf)
      totals(pdf)
      footer(pdf)
    end.render
  end

  private

  def header(pdf)
    top = pdf.cursor
    pdf.font_size(26) { pdf.text "INVOICE", style: :bold, character_spacing: 1.5 }
    pdf.fill_color DIM
    pdf.text "##{@document.id}", size: 11
    pdf.fill_color INK
    pdf.bounding_box([ pdf.bounds.width - 240, top ], width: 240) do
      pdf.text @org.name, size: 12, style: :bold, align: :right
      pdf.fill_color DIM
      pdf.text "Issued #{fmt_date @document.date}", size: 9.5, align: :right
      pdf.text "Due #{fmt_date @invoice.due_date}", size: 9.5, align: :right
      pdf.text "Reference #{@document.reference}", size: 9.5, align: :right if @document.reference.present?
      pdf.fill_color INK
    end
    pdf.move_down 26
  end

  def parties(pdf)
    top = pdf.cursor
    pdf.bounding_box([ 0, top ], width: pdf.bounds.width / 2 - 10) do
      label(pdf, "Billed to")
      pdf.text @document.counterparty.to_s, size: 11
      if (c = @document.contact)
        pdf.fill_color DIM
        [ c.email, c.address, [ c.city, c.region, c.postal_code ].compact_blank.join(", "), c.country ].compact_blank.each { |line| pdf.text line, size: 9.5 }
        pdf.fill_color INK
      end
    end
    pdf.bounding_box([ pdf.bounds.width / 2 + 10, top ], width: pdf.bounds.width / 2 - 10) do
      label(pdf, "Balance due")
      pdf.text money(@document.balance_due), size: 20, style: :bold
      pdf.fill_color DIM
      pdf.text "of #{money @document.total}", size: 9.5
      pdf.fill_color INK
    end
    pdf.move_down 26
  end

  def lines(pdf)
    rows = [ %w[Description Qty Unit Amount] ]
    @document.line_items.each do |li|
      rows << [ li.description.presence || li.account.name, fmt_qty(li.quantity), money(li.unit_amount), money(li.amount) ]
    end
    pdf.table(rows, width: pdf.bounds.width, column_widths: { 1 => 60, 2 => 90, 3 => 100 }, cell_style: { borders: [ :bottom ], border_color: RULE, border_width: 0.5, padding: [ 8, 4 ], size: 10 }) do |t|
      t.row(0).font_style = :bold
      t.row(0).size = 8
      t.row(0).text_color = DIM
      t.row(0).border_width = 1.5
      t.row(0).border_color = INK
      t.columns(1..3).align = :right
    end
    pdf.move_down 10
  end

  def totals(pdf)
    rows = [ [ "Subtotal", money(@document.subtotal) ] ]
    @document.line_ledger_legs[:taxes].each { |tax, amt| rows << [ tax.name, money(amt) ] }
    rows << [ "Total", money(@document.total) ]
    if @document.paid_amount.positive?
      rows << [ "Paid", "-#{money @document.paid_amount}" ]
      rows << [ "Balance due", money(@document.balance_due) ]
    end
    pdf.indent(pdf.bounds.width - 260) do
      pdf.table(rows, width: 260, column_widths: [ 150, 110 ], cell_style: { borders: [], padding: [ 5, 4 ], size: 10.5 }) do |t|
        t.columns(1).align = :right
        [ rows.index { |r| r[0] == "Total" }, (rows.size - 1 if @document.paid_amount.positive?) ].compact.each do |i|
          t.row(i).font_style = :bold
          t.row(i).borders = [ :top ]
          t.row(i).border_color = INK
          t.row(i).border_width = 1.5
        end
      end
    end
  end

  def footer(pdf)
    pdf.number_pages "Invoice ##{@document.id} · #{@org.name} · page <page> of <total>", at: [ 0, -20 ], width: pdf.bounds.width, align: :center, size: 8, color: DIM
  end

  def label(pdf, text)
    pdf.fill_color DIM
    pdf.text text.upcase, size: 7.5, character_spacing: 1.2
    pdf.fill_color INK
    pdf.move_down 3
  end

  def money(v)    = "$#{ActiveSupport::NumberHelper.number_to_delimited('%.2f' % v.to_d)}"
  def fmt_qty(q)  = q.to_d.frac.zero? ? q.to_i.to_s : q.to_d.to_s("F")
  def fmt_date(d) = d.strftime("%b %-d, %Y")
end

module ApplicationHelper
  # 16px stroke glyphs for the sidebar, drawn in currentColor so the active/hover
  # states in CSS carry them. Keyed by nav destination, not by shape.
  NAV_ICONS = {
    dashboard: %(<path d="M2.5 13.5V9M8 13.5V3M13.5 13.5V6.5"/>),
    contacts:  %(<circle cx="8" cy="5.5" r="2.5"/><path d="M3 13.5c0-2.5 2.2-4 5-4s5 1.5 5 4"/>),
    invoices:  %(<path d="M3.5 2h9v12l-2.25-1.3L8 14l-2.25-1.3L3.5 14z"/><path d="M6 5.5h4M6 8.5h4"/>),
    bills:     %(<path d="M4 2.5h8v11l-1.5-1-1.5 1-1.5-1-1.5 1-1.5-1-1.5 1z"/><path d="M6.5 6h3M6.5 8.5h3"/>),
    expenses:  %(<path d="M2.5 4.5h11v7h-11z"/><path d="M2.5 7h11"/><path d="M10.5 9.5h1.5"/>),
    deposits:  %(<path d="M8 13.5v-8M5 8.5 8 5.5l3 3"/><path d="M2.5 13.5h11"/>),
    transfers: %(<path d="M2.5 5.5h9l-2.5-2.5M13.5 10.5h-9l2.5 2.5"/>),
    journal:   %(<path d="M4 2.5h8v11H4z"/><path d="M4 5h-1.5M4 8h-1.5M4 11h-1.5"/><path d="M6.5 6h3M6.5 9h3"/>),
    accounts:  %(<path d="M8 2 14 5.5H2z"/><path d="M4 7v4.5M8 7v4.5M12 7v4.5"/><path d="M2.5 13.5h11"/>),
    banking:   %(<rect x="2" y="4" width="12" height="8.5" rx="1.5"/><path d="M2 7h12"/><path d="M4.5 10.5h3"/>),
    reports:   %(<path d="M2.5 2.5v11h11"/><path d="M5 11 7.5 7.5l2.5 2 3-4.5"/>),
    reconcile: %(<path d="M2.5 5.5h8l-2-2M13.5 10.5h-8l2 2"/>),
    imports:   %(<path d="M8 2.5v7M5.5 7 8 9.5 10.5 7"/><path d="M2.5 11.5v2h11v-2"/>),
    tax:       %(<circle cx="5" cy="5" r="1.75"/><circle cx="11" cy="11" r="1.75"/><path d="M12.5 3.5 3.5 12.5"/>),
    settings:  %(<path d="M2.5 5h11M2.5 11h11"/><circle cx="6" cy="5" r="1.75"/><circle cx="10.5" cy="11" r="1.75"/>)
  }.freeze

  def nav_icon(name)
    body = NAV_ICONS.fetch(name.to_sym)
    tag.svg(body.html_safe, viewBox: "0 0 16 16", fill: "none", stroke: "currentColor",
            "stroke-width": 1.4, "stroke-linecap": "round", "stroke-linejoin": "round",
            "aria-hidden": true)
  end

  # /invoices/:id, /bills/:id, ... for whichever type a document is.
  def document_path_for(document)
    public_send("#{document.documentable_name}_path", document)
  end

  def edit_document_path_for(document) = public_send("edit_#{document.documentable_name}_path", document)
  def void_document_path_for(document) = public_send("void_#{document.documentable_name}_path", document)
  def documents_path_for(document)     = public_send("#{document.documentable_name.pluralize}_path")

  # The form target for a new or existing document of its type.
  def document_form_options(document)
    document.persisted? ? { url: document_path_for(document), method: :patch } : { url: documents_path_for(document), method: :post }
  end

  # "Void Invoice #12? This removes its ledger postings, 2 payments ($750.00) and returns 2 bank lines to unmatched."
  def void_confirm_message(document)
    c = document.void_consequences
    parts = [ "its ledger postings" ]
    parts << "#{pluralize(c[:payments], 'payment')} (#{money(c[:paid])})" if c[:payments].positive?
    parts << "returns #{pluralize(c[:bank_lines], 'bank line')} to unmatched" if c[:bank_lines].positive?
    "Void #{document.label}? This removes #{parts.to_sentence}."
  end

  def money(amount)
    "$#{number_with_precision(amount, precision: 2, delimiter: ',')}"
  end

  # +$1,000.00 / -$8.00 for statement lines.
  def signed_money(amount)
    "#{amount.negative? ? '-' : '+'}#{money(amount.abs)}"
  end

  def status_badge(status)
    tag.span(status, class: "badge badge-#{status}")
  end

  # Sidebar entry: icon + label, marked active when the current controller is one
  # of the sections it covers.
  def nav_item(label, path, icon:, sections: nil)
    sections = Array(sections || icon)
    active = sections.any? { |s| controller_path == s.to_s || controller_path.start_with?("#{s}/") }
    link_to(path, class: ("active" if active), "aria-current": ("page" if active)) do
      safe_join([ nav_icon(icon), tag.span(label) ])
    end
  end
end

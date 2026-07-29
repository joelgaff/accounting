import { Controller } from "@hotwired/stimulus"

// Manages nested line-item rows on invoice / expense forms.
// - Adds new rows from a <template> using the standard Rails
//   fields_for child_index: "NEW_RECORD" trick.
// - Marks removed rows with _destroy=1 (so persisted records get
//   deleted server-side) and hides the row.
// - Live-recomputes per-row Amount, plus Subtotal / Tax / Total
//   totals in the tfoot, on any input.
export default class extends Controller {
  static targets = ["rows", "template", "subtotal", "tax", "total"]
  static values = { index: Number }

  connect() {
    this.recalc()
  }

  add(event) {
    event.preventDefault()
    const html = this.templateTarget.innerHTML.replace(/NEW_RECORD/g, this.indexValue)
    this.rowsTarget.insertAdjacentHTML("beforeend", html)
    this.indexValue += 1
    this.recalc()
  }

  remove(event) {
    event.preventDefault()
    const row = event.target.closest("tr")
    const destroyField = row.querySelector('input[name*="[_destroy]"]')
    if (destroyField) {
      destroyField.value = "1"
      row.style.display = "none"
    } else {
      row.remove()
    }
    this.recalc()
  }

  recalc() {
    let subtotal = 0
    let tax = 0

    this.rowsTarget.querySelectorAll("tr").forEach(row => {
      if (row.style.display === "none") return
      const qty  = parseFloat(row.querySelector('input[name*="[quantity]"]')?.value || 0) || 0
      const unit = parseFloat(row.querySelector('input[name*="[unit_amount]"]')?.value || 0) || 0
      const amt  = Math.round(qty * unit * 100) / 100
      const rowTotalEl = row.querySelector('[data-line-items-target="rowTotal"]')
      if (rowTotalEl) rowTotalEl.textContent = this._fmt(amt)

      subtotal += amt

      const taxSelect = row.querySelector('select[name*="[tax_rate_id]"]')
      if (taxSelect && taxSelect.value) {
        const rates = JSON.parse(taxSelect.dataset.taxRates || "{}")
        const rate  = rates[taxSelect.value] || 0
        tax += Math.round(amt * rate * 100) / 100
      }
    })

    if (this.hasSubtotalTarget) this.subtotalTarget.textContent = this._fmt(subtotal)
    if (this.hasTaxTarget)      this.taxTarget.textContent      = this._fmt(tax)
    if (this.hasTotalTarget)    this.totalTarget.textContent    = this._fmt(subtotal + tax)
  }

  _fmt(n) {
    return "$" + n.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ",")
  }
}

import { Controller } from "@hotwired/stimulus"

// Manages nested line-item rows on invoice / bill / expense / deposit forms.
// - Adds new rows from a <template> using the standard Rails
//   fields_for child_index: "NEW_RECORD" trick.
// - Marks removed rows with _destroy=1 (so persisted records get
//   deleted server-side) and hides the row.
// - Qty × Unit fills Amount; typing an Amount back-solves the Unit price
//   (with Qty defaulting to 1), so either column can be the one you enter.
// - Live-recomputes Subtotal / Tax / Total in the tfoot on any input.
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

  // Amount typed directly: keep qty (default 1) and derive the unit price.
  amountChanged(event) {
    const row    = event.target.closest("tr")
    const qtyEl  = this._qty(row)
    const unitEl = this._unit(row)
    const amount = this._num(event.target.value)
    let qty = this._num(qtyEl?.value)
    if (!qty) { qty = 1; if (qtyEl) qtyEl.value = 1 }
    if (unitEl) unitEl.value = event.target.value === "" ? "" : (Math.round((amount / qty) * 100) / 100).toFixed(2)
    this.recalc({ skipAmount: row })
  }

  recalc(opts = {}) {
    let subtotal = 0
    let tax = 0

    this.rowsTarget.querySelectorAll("tr").forEach(row => {
      if (row.style.display === "none") return
      const qty  = this._num(this._qty(row)?.value)
      const unit = this._num(this._unit(row)?.value)
      const amt  = Math.round(qty * unit * 100) / 100
      const amountEl = row.querySelector('[data-line-items-target="amount"]')
      if (amountEl && row !== opts.skipAmount) {
        amountEl.value = this._unit(row)?.value === "" ? "" : amt.toFixed(2)
      }

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

  _qty(row)  { return row.querySelector('input[name*="[quantity]"]') }
  _unit(row) { return row.querySelector('input[name*="[unit_amount]"]') }
  _num(v)    { const n = parseFloat(v); return Number.isFinite(n) ? n : 0 }

  _fmt(n) {
    return "$" + n.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ",")
  }
}

import { Controller } from "@hotwired/stimulus"

// Nested lines for a manual journal entry. Add/remove rows, plus
// a live debit / credit totals row that turns the "Difference"
// cell green when debits === credits (i.e. entry is balanced).
export default class extends Controller {
  static targets = ["rows", "template", "debitTotal", "creditTotal", "difference"]
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
    let debit = 0
    let credit = 0
    this.rowsTarget.querySelectorAll("tr").forEach(row => {
      if (row.style.display === "none") return
      debit  += parseFloat(row.querySelector('input[name*="[debit_amount]"]')?.value  || 0) || 0
      credit += parseFloat(row.querySelector('input[name*="[credit_amount]"]')?.value || 0) || 0
    })
    if (this.hasDebitTotalTarget)  this.debitTotalTarget.textContent  = this._fmt(debit)
    if (this.hasCreditTotalTarget) this.creditTotalTarget.textContent = this._fmt(credit)
    if (this.hasDifferenceTarget) {
      const diff = Math.round((debit - credit) * 100) / 100
      this.differenceTarget.textContent = this._fmt(diff)
      this.differenceTarget.style.color = diff === 0 ? "var(--success)" : "var(--danger)"
      this.differenceTarget.style.fontWeight = "600"
    }
  }

  _fmt(n) {
    return "$" + Math.abs(n).toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ",") + (n < 0 ? " (Cr)" : "")
  }
}

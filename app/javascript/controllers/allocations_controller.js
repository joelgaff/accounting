import { Controller } from "@hotwired/stimulus"

// Split rows for one statement line: add/remove document rows and show what
// is left of the line as amounts are typed. The server re-checks the sums.
export default class extends Controller {
  static targets = ["rows", "template", "remaining"]
  static values  = { total: Number, index: Number }

  connect() { this.recalc() }

  add(event) {
    event.preventDefault()
    this.rowsTarget.insertAdjacentHTML("beforeend", this.templateTarget.innerHTML.replace(/NEW_RECORD/g, this.indexValue))
    this.indexValue += 1
    this.recalc()
  }

  remove(event) {
    event.preventDefault()
    event.target.closest("tr").remove()
    this.recalc()
  }

  recalc() {
    let used = 0
    this.rowsTarget.querySelectorAll('input[name$="[amount]"]').forEach(input => { used += parseFloat(input.value || 0) || 0 })
    const left = Math.round((this.totalValue - used) * 100) / 100
    if (this.hasRemainingTarget) {
      this.remainingTarget.textContent = "$" + left.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ",")
      this.remainingTarget.classList.toggle("neg", left < 0)
    }
  }
}

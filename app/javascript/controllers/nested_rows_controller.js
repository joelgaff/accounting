import { Controller } from "@hotwired/stimulus"

// Add and remove nested rows on a form: new rows come from a <template>
// with NEW_RECORD placeholders; a saved row's remove ticks its _destroy
// field and hides it, an unsaved row is simply dropped.
export default class extends Controller {
  static targets = ["rows", "template"]
  static values  = { index: Number }

  add(event) {
    event.preventDefault()
    this.rowsTarget.insertAdjacentHTML("beforeend", this.templateTarget.innerHTML.replace(/NEW_RECORD/g, this.indexValue))
    this.indexValue += 1
    this.rowsTarget.lastElementChild?.querySelector("input[type=text]")?.focus()
  }

  remove(event) {
    event.preventDefault()
    const row = event.target.closest("tr")
    const destroy = row.querySelector('input[name*="[_destroy]"]')
    if (destroy) { destroy.value = "1"; row.hidden = true } else { row.remove() }
  }
}

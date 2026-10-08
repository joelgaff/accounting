import { Controller } from "@hotwired/stimulus"

// A bottom sheet: hidden at rest, opened by a trigger, closed by the dimmer,
// Escape, or the trigger again. Presentation only; the server renders what
// the sheet holds.
export default class extends Controller {
  static targets = ["panel", "dimmer", "trigger"]

  connect() { this.close() }

  toggle(event) {
    event?.preventDefault()
    this.panelTarget.hidden ? this.open() : this.close()
  }

  open() {
    this.panelTarget.hidden = false
    if (this.hasDimmerTarget) this.dimmerTarget.hidden = false
    this.triggerTargets.forEach(t => t.setAttribute("aria-expanded", "true"))
    document.body.classList.add("sheet-open")
    this.panelTarget.querySelector("a, button")?.focus()
  }

  close() {
    this.panelTarget.hidden = true
    if (this.hasDimmerTarget) this.dimmerTarget.hidden = true
    this.triggerTargets.forEach(t => t.setAttribute("aria-expanded", "false"))
    document.body.classList.remove("sheet-open")
  }

  keydown(event) {
    if (event.key === "Escape" && !this.panelTarget.hidden) { this.close(); event.preventDefault() }
  }
}

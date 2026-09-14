import { Controller } from "@hotwired/stimulus"

// A row of tab buttons and the panels they reveal. Only presentation: the
// server decides which segments exist and which one opens first.
export default class extends Controller {
  static targets = ["tab", "panel"]
  static values  = { active: String }

  connect() {
    const first = this.tabTargets[0]?.dataset.segment
    const wanted = this.tabTargets.some(t => t.dataset.segment === this.activeValue) ? this.activeValue : first
    this.show(wanted)
  }

  select(event) {
    this.show(event.currentTarget.dataset.segment)
  }

  show(name) {
    this.panelTargets.forEach(p => { p.hidden = p.dataset.segment !== name })
    this.tabTargets.forEach(t => t.setAttribute("aria-selected", t.dataset.segment === name))
  }
}

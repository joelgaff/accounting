import { Controller } from "@hotwired/stimulus"

// A section folded behind a button on small screens. The body carries the
// hidden attribute at rest; wide screens show it regardless (CSS), so the
// button only matters where it is visible.
export default class extends Controller {
  static targets = ["trigger", "body"]

  toggle() {
    const open = this.bodyTarget.hidden
    this.bodyTarget.hidden = !open
    this.triggerTargets.forEach(t => t.setAttribute("aria-expanded", String(open)))
  }
}

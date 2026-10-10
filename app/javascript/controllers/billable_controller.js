import { Controller } from "@hotwired/stimulus"

// The billable-expenses panel on an invoice form. Picking a customer points
// the frame at their unbilled costs; ticking a cost hands its rows to the
// line-items controller; unticking takes them back out. Changing the markup
// re-fetches the panel, which clears what was ticked.
export default class extends Controller {
  static targets = ["frame", "markup"]
  static values  = { url: String }   // contact_billable_expenses_path with __ID__ for the contact

  customerChanged(event) {
    this.clearPicked()
    const id = event.target.value
    if (!id) { this.frameTarget.removeAttribute("src"); this.frameTarget.innerHTML = ""; return }
    this.frameTarget.src = this.urlValue.replace("__ID__", id)
  }

  markupChanged() {
    this.clearPicked()
    const url = new URL(this.frameTarget.src, window.location.href)
    url.searchParams.set("markup", this.markupTarget.value || "0")
    this.frameTarget.src = url.toString()
  }

  // A fresh panel (new customer, new markup) starts with nothing ticked, so
  // rows picked from the old one go, even ones ticked while it was loading.
  panelLoaded() {
    this.clearPicked()
  }

  toggle(event) {
    const box  = event.target
    const cost = box.closest("li[data-cost-id]")
    if (box.checked) {
      cost.querySelectorAll("template").forEach(t => this.lineItems.insert(t.innerHTML))
    } else {
      this.lineItems.dropUnsaved(`tr[data-rebills="${box.dataset.costId}"]`)
    }
  }

  clearPicked() {
    this.lineItems?.dropUnsaved("tr[data-rebills]")
  }

  get lineItems() {
    const el = this.element.querySelector('[data-controller~="line-items"]')
    return el && this.application.getControllerForElementAndIdentifier(el, "line-items")
  }
}

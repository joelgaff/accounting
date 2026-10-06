import { Controller } from "@hotwired/stimulus"

// A strip of tab buttons and the panels they reveal in a drawer row beneath.
// Nothing is open at rest; clicking a tab opens its panel, clicking it again
// (or Escape) closes it. Enter on the focused row opens the default panel.
// Only presentation: the server decides which segments exist.
export default class extends Controller {
  static targets = ["tab", "panel", "drawer"]
  static values  = { default: String }

  select(event) {
    const name = event.currentTarget.dataset.segment
    this.show(this.openName === name ? null : name)
  }

  keydown(event) {
    if (event.key === "Escape" && this.openName) { this.show(null); event.preventDefault(); return }
    if (event.key === "Enter" && event.target.classList.contains("recon-row") && !this.openName) {
      const first = this.tabTargets.find(t => t.dataset.segment === this.defaultValue) || this.tabTargets[0]
      if (first) { this.show(first.dataset.segment); event.preventDefault() }
    }
  }

  show(name) {
    this.openName = name
    this.panelTargets.forEach(p => { p.hidden = p.dataset.segment !== name })
    this.tabTargets.forEach(t => t.setAttribute("aria-selected", t.dataset.segment === name))
    if (this.hasDrawerTarget) this.drawerTarget.hidden = !name
    if (!name) return
    const panel = this.panelTargets.find(p => p.dataset.segment === name)
    const control = [...panel.querySelectorAll("input:not([type=hidden]), select, button")].find(el => el.offsetParent !== null)
    control?.focus()
  }
}

// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// Long dropdowns become searchable pickers (controllers/combobox_controller.js).
// Anything with this many options or more qualifies; data-no-combobox opts out.
const COMBOBOX_MIN_OPTIONS = 8

function enhanceSelects(root = document) {
  root.querySelectorAll("select").forEach(select => {
    if (select.multiple || select.dataset.noCombobox !== undefined || select.dataset.controller?.includes("combobox")) return
    if (select.options.length < COMBOBOX_MIN_OPTIONS) return
    select.dataset.controller = [select.dataset.controller, "combobox"].filter(Boolean).join(" ")
  })
}

document.addEventListener("turbo:load", () => enhanceSelects())
document.addEventListener("turbo:frame-load", e => enhanceSelects(e.target))
document.addEventListener("turbo:before-stream-render", e => {
  const render = e.detail.render
  e.detail.render = stream => { render(stream); enhanceSelects() }
})
new MutationObserver(records => {
  records.forEach(r => r.addedNodes.forEach(n => { if (n.nodeType === 1) enhanceSelects(n.parentNode || n) }))
}).observe(document.documentElement, { childList: true, subtree: true })

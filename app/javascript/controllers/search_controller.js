import { Controller } from "@hotwired/stimulus"

// A search box that submits its form as you type, a beat after the last
// keystroke. The form targets a Turbo frame, so only the list redraws and the
// box keeps its text and focus. Presentation only: the server does the search.
export default class extends Controller {
  static values = { delay: { type: Number, default: 200 } }

  submit() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.element.requestSubmit(), this.delayValue)
  }

  disconnect() { clearTimeout(this.timer) }
}

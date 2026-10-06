import { Controller } from "@hotwired/stimulus"

// A terminal-style spinner: cycles braille frames in place.
export default class extends Controller {
  static FRAMES = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

  connect() {
    let i = 0
    this.timer = setInterval(() => {
      i = (i + 1) % this.constructor.FRAMES.length
      this.element.textContent = this.constructor.FRAMES[i]
    }, 80)
  }

  disconnect() {
    clearInterval(this.timer)
  }
}

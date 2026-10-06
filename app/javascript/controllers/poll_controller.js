import { Controller } from "@hotwired/stimulus"

// Reloads the enclosing Turbo Frame on an interval while `active` is true.
// The server renders the next frame with active=false once the work is
// done, and the fresh controller instance simply doesn't start a timer.
export default class extends Controller {
  static values = { interval: { type: Number, default: 2000 }, active: Boolean }

  connect() {
    if (!this.activeValue) return
    this.timer = setInterval(() => this.frame?.reload(), this.intervalValue)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  get frame() {
    return this.element.closest("turbo-frame")
  }
}

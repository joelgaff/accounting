import { Controller } from "@hotwired/stimulus"

// Paint the chosen theme the moment it is clicked, then save it. The theme
// lives on <html data-theme>, which Turbo Drive keeps across visits, so the
// change holds until the server renders the saved value on a full load.
export default class extends Controller {
  static COLORS = { dark: "#060a12", light: "#eef2f7" }

  change(event) {
    const theme = event.target.value
    document.documentElement.dataset.theme = theme
    document.querySelector('meta[name="theme-color"]')?.setAttribute("content", this.constructor.COLORS[theme] || this.constructor.COLORS.dark)
    this.element.requestSubmit()
  }
}

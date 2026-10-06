import { Controller } from "@hotwired/stimulus"

// Submit the form as soon as a control changes (radio groups, selects).
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}

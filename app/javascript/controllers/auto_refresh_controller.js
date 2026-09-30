import { Controller } from "@hotwired/stimulus"

// Refreshes the page every few seconds while it shows work in progress (a running employee import). The page opts in
// to morphing refreshes, so the new render is merged in place; once the work is done the new render no longer has
// this element, which stops the refreshes.
export default class extends Controller {
  static values = { interval: { type: Number, default: 3000 } }

  connect() {
    this.timer = setInterval(() => {
      if (!document.hidden) Turbo.visit(window.location.href, { action: "replace" })
    }, this.intervalValue)
  }

  disconnect() {
    clearInterval(this.timer)
  }
}

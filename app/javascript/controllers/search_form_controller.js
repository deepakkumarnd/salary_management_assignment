import { Controller } from "@hotwired/stimulus"

// Submits the employee search form as the user works: 300 ms after they stop typing, and straight away when a filter
// changes. Each submission is a Turbo visit that advances the URL, so the URL always holds the search.
// Without JavaScript it's an ordinary GET form with a Search button.
export default class extends Controller {
  static targets = ["query"]

  // The search box is data-turbo-permanent (it keeps focus while results re-render), so after Back/Forward it
  // still holds the old text: take the URL's value unless the user is typing in it.
  queryTargetConnected(input) {
    if (document.activeElement === input) return
    input.value = new URLSearchParams(window.location.search).get("q") || ""
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  search() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.element.requestSubmit(), 300)
  }

  submit() {
    clearTimeout(this.timer)
    this.element.requestSubmit()
  }

  // Keep the URL short and shareable: leave out empty fields and defaults (data-default="current") by disabling them
  // for this submission only. Runs on the form before Turbo reads it at the document.
  clean() {
    const skipped = [...this.element.elements].filter((field) =>
      field.name && !field.disabled && (field.value.trim() === "" || field.value === field.dataset.default))
    skipped.forEach((field) => { field.disabled = true })
    requestAnimationFrame(() => skipped.forEach((field) => { field.disabled = false }))
  }
}

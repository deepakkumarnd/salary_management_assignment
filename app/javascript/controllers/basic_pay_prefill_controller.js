import { Controller } from "@hotwired/stimulus"

// Pre-fills a new hire's starting basic with the pay structure's default for the chosen country + role. A value the
// user typed is never overwritten; one we pre-filled is replaced when the country or role changes.
//
//   defaults: { "<country_id>:<job_role_id>": "12,00,000", … }
export default class extends Controller {
  static targets = ["country", "role", "basic"]
  static values = { defaults: Object }

  update() {
    const value = this.defaultsValue[`${this.countryTarget.value}:${this.roleTarget.value}`]
    const basic = this.basicTarget
    if (value === undefined || !(basic.value === "" || basic.value === basic.dataset.prefilled)) return

    basic.value = value
    basic.dataset.prefilled = value
    basic.dispatchEvent(new Event("input", { bubbles: true }))
  }
}

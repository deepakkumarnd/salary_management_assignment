import { Controller } from "@hotwired/stimulus"

// Live pay breakdown for a form: whenever a watched field changes, reload the preview Turbo Frame from the server
// with the fields' current values (the calculation itself never runs in JavaScript).
//
//   <form data-controller="pay-preview" data-pay-preview-url-value="/pay_structures/preview">
//     <input data-pay-preview-target="field" data-pay-preview-param="basic_pay"
//            data-action="input->pay-preview#refresh">
//     <turbo-frame id="pay_preview" data-pay-preview-target="frame"></turbo-frame>
export default class extends Controller {
  static targets = ["field", "frame"]
  static values = { url: String }

  connect() {
    this.load()
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  refresh() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.load(), 250)
  }

  load() {
    const params = new URLSearchParams()
    this.fieldTargets.forEach((field) => params.set(field.dataset.payPreviewParam, field.value))
    this.frameTarget.src = `${this.urlValue}?${params}`
  }
}

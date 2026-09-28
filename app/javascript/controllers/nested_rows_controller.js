import { Controller } from "@hotwired/stimulus"

// Adds and removes rows of a nested-attributes form (e.g. allowances) without a round trip.
// The <template> holds one blank row whose field names use NEW_RECORD as the index; each added row gets a unique one.
//
//   <div data-controller="nested-rows">
//     <tbody data-nested-rows-target="rows">…</tbody>
//     <template data-nested-rows-target="template"><tr>…</tr></template>
//     <button type="submit" data-action="nested-rows#add">Add</button>   (without JS, the server adds the row)
//   </div>
export default class extends Controller {
  static targets = ["rows", "template"]

  add(event) {
    event.preventDefault()
    const index = `${Date.now()}${Math.floor(Math.random() * 1000)}`
    this.rowsTarget.insertAdjacentHTML("beforeend", this.templateTarget.innerHTML.replaceAll("NEW_RECORD", index))
    this.rowsTarget.lastElementChild.querySelector("input:not([type=hidden])")?.focus()
  }

  remove(event) {
    event.preventDefault()
    event.currentTarget.closest("tr").remove()
  }
}

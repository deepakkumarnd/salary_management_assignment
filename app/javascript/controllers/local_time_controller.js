import { Controller } from "@hotwired/stimulus"

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
const pad = (number) => String(number).padStart(2, "0")

// Shows a <time datetime="…UTC…"> in the viewer's own time zone, e.g. "28 Sep 2026, 15:10", with the full date and
// zone in the tooltip. The server renders the same format in UTC as the fallback (see TimeHelper#local_time).
// Built by hand rather than with Intl month names, which differ between browsers ("Sep" / "Sept").
export default class extends Controller {
  connect() {
    const time = new Date(this.element.getAttribute("datetime"))
    if (Number.isNaN(time.getTime())) return

    this.element.textContent =
      `${time.getDate()} ${MONTHS[time.getMonth()]} ${time.getFullYear()}, ${pad(time.getHours())}:${pad(time.getMinutes())}`
    this.element.title = time.toLocaleString(undefined, { dateStyle: "full", timeStyle: "long" })
  }
}

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["filter"]

  filter() {
    const term = this.filterTarget.value.toLowerCase().trim()
    const tableId = this.filterTarget.dataset.tableId
    const table = document.getElementById(tableId)
    if (!table) return

    // Packet rows may be followed by a collapsible detail row (the
    // Wireshark-style field tree) — match on the summary row's own text
    // only, and mirror the result onto its detail row, so filtering never
    // shows an expanded detail block whose summary row got hidden (or vice
    // versa, based on the detail row's own unrelated text matching).
    table.querySelectorAll("tbody > tr:not(.collapse)").forEach(row => {
      const visible = term === "" || row.textContent.toLowerCase().includes(term)
      row.hidden = !visible

      const detailRow = row.nextElementSibling
      if (detailRow && detailRow.classList.contains("collapse")) {
        detailRow.hidden = !visible
      }
    })
  }
}

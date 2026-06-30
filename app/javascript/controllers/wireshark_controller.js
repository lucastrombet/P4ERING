import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["filter"]

  filter() {
    const term = this.filterTarget.value.toLowerCase().trim()
    const tableId = this.filterTarget.dataset.tableId
    const table = document.getElementById(tableId)
    if (!table) return

    table.querySelectorAll("tbody tr").forEach(row => {
      row.hidden = term !== "" && !row.textContent.toLowerCase().includes(term)
    })
  }
}

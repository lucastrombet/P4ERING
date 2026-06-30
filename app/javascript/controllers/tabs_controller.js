import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["btn", "pane"]

  show(event) {
    const clicked = event.currentTarget
    const targetId = clicked.dataset.tabPane

    this.btnTargets.forEach(b => b.classList.toggle("active", b === clicked))
    this.paneTargets.forEach(p => {
      const active = p.id === targetId
      p.classList.toggle("show",   active)
      p.classList.toggle("active", active)
    })
  }
}

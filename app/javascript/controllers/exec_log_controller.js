import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this._observer = new MutationObserver(() => {
      this.element.scrollTop = this.element.scrollHeight
    })
    this._observer.observe(this.element, { childList: true })
  }

  disconnect() {
    this._observer?.disconnect()
  }

  // Force-reconnect the ActionCable stream and clear the log.
  refresh() {
    const source = document.querySelector("turbo-cable-stream-source")
    if (source) {
      source.replaceWith(source.cloneNode(false))
    }
    this.element.textContent = ""
  }
}

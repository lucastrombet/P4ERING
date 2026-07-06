import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

// Command/response consoles for the P4CHECKERS interactive sandbox. Not a
// real PTY — each Enter press does one round trip (type a move, see the
// reply appended below), matching the underlying protocol (one UDP
// datagram in, one reply out).
export default class extends Controller {
  static targets = ["scrollback", "input"]
  static values = { sessionId: Number }

  connect() {
    this.subscription = consumer.subscriptions.create(
      { channel: "GameSessionChannel", id: this.sessionIdValue },
      {
        received: (data) => this.handleReceived(data),
      }
    )
  }

  disconnect() {
    if (this.subscription) this.subscription.unsubscribe()
  }

  send(event) {
    event.preventDefault()
    const host = event.currentTarget.dataset.host
    const input = this.inputTargets.find((el) => el.dataset.host === host)
    if (!input || !input.value.trim()) return

    const command = input.value.trim()
    this.appendLine(host, `> ${command}`)
    input.value = ""

    this.subscription.perform("receive", { host, command })
  }

  handleReceived(data) {
    if (data.type !== "console_reply") return
    this.appendLine(data.host, data.output)
  }

  appendLine(host, text) {
    const scrollback = this.scrollbackTargets.find((el) => el.dataset.host === host)
    if (!scrollback) return
    scrollback.textContent += (scrollback.textContent ? "\n" : "") + text
    scrollback.scrollTop = scrollback.scrollHeight
  }
}

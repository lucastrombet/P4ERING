import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

// Command/response consoles for the P4CHECKERS interactive sandbox. Not a
// real PTY — each Enter press does one round trip (type a move, see the
// reply appended below), matching the underlying protocol (one UDP
// datagram in, one reply out).
//
// The subscription's health is tracked explicitly (rather than assumed)
// because a silently-dead subscription is indistinguishable from a slow
// network to the user: typed commands would just vanish. connected /
// disconnected / rejected are wired up so the UI always reflects reality,
// sends are blocked while not connected, and a dropped subscription is
// retried automatically with backoff.
const MAX_RECONNECT_DELAY_MS = 15000
const INITIAL_RECONNECT_DELAY_MS = 1000

export default class extends Controller {
  static targets = ["scrollback", "input", "submit", "status"]
  static values = { sessionId: Number }

  connect() {
    this.torndown = false
    this.reconnectDelay = INITIAL_RECONNECT_DELAY_MS
    this.reconnectTimer = null
    this.subscribeChannel()
  }

  disconnect() {
    this.torndown = true
    this.clearReconnectTimer()
    this.teardownSubscription()
  }

  subscribeChannel() {
    // Defensive: never leave two live subscriptions for the same session
    // outstanding at once (e.g. if connect() somehow runs again before a
    // prior disconnect() fully tore down).
    this.teardownSubscription()
    this.setStatus("connecting")

    this.subscription = consumer.subscriptions.create(
      { channel: "GameSessionChannel", id: this.sessionIdValue },
      {
        connected: () => this.handleConnected(),
        disconnected: () => this.handleDisconnected(),
        rejected: () => this.handleRejected(),
        received: (data) => this.handleReceived(data),
      }
    )
  }

  teardownSubscription() {
    if (this.subscription) {
      this.subscription.unsubscribe()
      this.subscription = null
    }
  }

  handleConnected() {
    this.reconnectDelay = INITIAL_RECONNECT_DELAY_MS
    this.clearReconnectTimer()
    this.setStatus("connected")
  }

  handleDisconnected() {
    if (this.torndown) return
    this.setStatus("disconnected")
    this.scheduleReconnect()
  }

  handleRejected() {
    if (this.torndown) return
    this.clearReconnectTimer()
    this.setStatus("rejected")
  }

  scheduleReconnect() {
    if (this.torndown || this.reconnectTimer) return
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null
      if (this.torndown) return
      this.reconnectDelay = Math.min(this.reconnectDelay * 2, MAX_RECONNECT_DELAY_MS)
      this.subscribeChannel()
    }, this.reconnectDelay)
  }

  clearReconnectTimer() {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer)
      this.reconnectTimer = null
    }
  }

  setStatus(state) {
    this.connectionState = state

    const connected = state === "connected"
    this.inputTargets.forEach((el) => (el.disabled = !connected))
    this.submitTargets.forEach((el) => (el.disabled = !connected))

    if (!this.hasStatusTarget) return

    const badgeClass = {
      connecting: "badge bg-secondary",
      connected: "badge bg-success",
      disconnected: "badge bg-warning text-dark",
      rejected: "badge bg-danger",
    }[state]

    this.statusTarget.className = badgeClass
    this.statusTarget.textContent = this.statusTextValueFor(state)
  }

  statusTextValueFor(state) {
    return this.statusTarget.dataset[`${state}Text`] || state
  }

  send(event) {
    event.preventDefault()
    const host = event.currentTarget.dataset.host
    const input = this.inputTargets.find((el) => el.dataset.host === host)
    if (!input || !input.value.trim()) return

    if (this.connectionState !== "connected") {
      this.appendLine(host, this.statusTarget?.dataset.blockedNotice || "[not connected]")
      return
    }

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

import { Controller } from "@hotwired/stimulus"

// Manages the exercise form's traffic-mapping rows: dynamic add/remove of
// nested ExerciseTrafficGenerator fields, from/to host options read live
// from the topology builder's hidden JSON output, and a per-row preview of
// the iperf client command that will actually run.
export default class extends Controller {
  static targets = ["rows", "template", "hostSelect", "preview", "row", "destroyFlag"]
  static values = { commands: Object }

  connect() {
    this.rowTargets.forEach((row) => this.updatePreview(row))
  }

  add() {
    const html = this.templateTarget.innerHTML.replace(/NEW_RECORD/g, Date.now())
    this.rowsTarget.insertAdjacentHTML("beforeend", html)
  }

  remove(event) {
    const row = event.target.closest(".traffic-mapping-row")
    const idField = row.querySelector('input[name*="[id]"]')
    if (idField && idField.value) {
      // Persisted row: flag for destruction and hide, so the id survives
      // the round-trip and Rails deletes it.
      row.querySelector('input[name*="[_destroy]"]').value = "1"
      row.classList.add("d-none")
    } else {
      row.remove()
    }
  }

  // Host names come from the topology builder, which rewrites its hidden
  // JSON field without firing events — so options are refreshed at
  // interaction time (select focus), always reflecting the current builder
  // state, including hosts added seconds ago.
  refreshHosts(event) {
    const select = event.target
    const current = select.value
    const blank = select.querySelector('option[value=""]')

    select.innerHTML = ""
    if (blank) select.appendChild(blank)

    for (const host of this.topologyHosts()) {
      const opt = document.createElement("option")
      opt.value = opt.textContent = host
      if (host === current) opt.selected = true
      select.appendChild(opt)
    }

    // Keep a saved value visible even if its host vanished from the
    // topology — the model validation will explain on submit.
    if (current && !this.topologyHosts().includes(current)) {
      const opt = document.createElement("option")
      opt.value = opt.textContent = current
      opt.selected = true
      select.appendChild(opt)
    }
  }

  preview(event) {
    this.updatePreview(event.target.closest(".traffic-mapping-row"))
  }

  updatePreview(row) {
    const genId = row.querySelector('select[name*="[traffic_generator_id]"]')?.value
    const to = row.querySelector('select[name*="[to_host]"]')?.value
    const el = row.querySelector('[data-traffic-mappings-target="preview"]')
    if (!el) return
    const template = this.commandsValue[genId]
    el.textContent = template ? template.replace("{to}", to || "<to>") : ""
  }

  topologyHosts() {
    const field = document.getElementById("topology_json_output")
    if (!field || !field.value) return []
    try {
      const topo = JSON.parse(field.value)
      return (topo.connections || []).map((c) => c.host_name).filter(Boolean)
    } catch {
      return []
    }
  }
}

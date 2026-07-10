import { Controller } from "@hotwired/stimulus"

// Structured editor for SubmissionEvaluator's evaluation_criteria JSON.
// The textarea (jsonTarget) stays the real form field; this controller
// renders its checks as rows and serializes edits back on every change.
// Anything it can't faithfully represent (unknown kinds/keys, multi-key
// filters) leaves it in raw-JSON mode so nothing is silently dropped.
//
// Layer/field names mirror what p4exec's pcap.py decodes into the
// structured captures — keep the two in sync.
const LAYER_FIELDS = {
  ethernet: ["src_mac", "dst_mac", "ethertype"],
  ipv4:     ["src", "dst", "ttl", "protocol"],
  ipv6:     ["src", "dst", "hop_limit", "next_header"],
  icmp:     ["type", "code", "id", "seq"],
  tcp:      ["src_port", "dst_port", "seq", "ack", "flags"],
  udp:      ["src_port", "dst_port", "length"],
}
const CHECKSUM_LAYERS = ["ipv4", "icmp", "tcp", "udp"]

const KNOWN_KEYS = {
  transformation: ["kind", "from", "to", "layer", "field", "op", "value", "filter"],
  count:          ["kind", "capture", "filter", "op", "value"],
  checksum:       ["kind", "capture", "layer"],
  duplication:    ["kind", "from", "to", "op", "value", "filter"],
}
const KIND_OPS = {
  transformation: ["equals", "unchanged", "changed"],
  count:          ["equals", "lte", "gte"],
  duplication:    ["equals", "lte", "gte"],
}

export default class extends Controller {
  static targets = ["json", "builder", "checks", "warning", "rawToggle"]
  static values = { labels: Object }

  connect() {
    this.checks = this.parseChecks()
    if (this.checks === null) {
      this.enterRawMode(true)
    } else {
      this.jsonTarget.classList.add("d-none")
      this.renderAll()
    }
  }

  // ── Modes ────────────────────────────────────────────────────────────────

  parseChecks() {
    const raw = this.jsonTarget.value.trim()
    if (!raw) return []
    let parsed
    try { parsed = JSON.parse(raw) } catch { return null }
    if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) return null
    const extraTop = Object.keys(parsed).filter((k) => k !== "checks")
    if (extraTop.length > 0) return null
    const checks = parsed.checks || []
    if (!Array.isArray(checks)) return null
    return checks.every((c) => this.representable(c)) ? checks : null
  }

  representable(check) {
    const known = KNOWN_KEYS[check.kind]
    if (!known) return false
    if (!Object.keys(check).every((k) => known.includes(k))) return false
    if (check.filter !== undefined) {
      if (typeof check.filter !== "object" || check.filter === null) return false
      const keys = Object.keys(check.filter)
      if (!keys.includes("layer") || keys.length > 2) return false
    }
    return true
  }

  enterRawMode(unrepresentable = false) {
    this.builderTarget.classList.add("d-none")
    this.rawToggleTarget.classList.add("d-none")
    this.jsonTarget.classList.remove("d-none")
    if (unrepresentable) this.warningTarget.classList.remove("d-none")
  }

  toggleRaw(event) {
    event.preventDefault()
    this.serialize()
    this.enterRawMode(false)
  }

  // ── Rendering ────────────────────────────────────────────────────────────

  renderAll() {
    this.checksTarget.innerHTML = ""
    this.checks.forEach((check, i) => this.checksTarget.appendChild(this.renderCheck(check, i)))
  }

  renderCheck(check, index) {
    const L = this.labelsValue
    const card = document.createElement("div")
    card.className = "card mb-2 criteria-check"
    card.dataset.index = index

    const kindOptions = Object.entries(L.kinds)
      .map(([k, label]) => `<option value="${k}" ${check.kind === k ? "selected" : ""}>${label}</option>`)
      .join("")

    card.innerHTML = `
      <div class="card-header py-1 d-flex align-items-center gap-2">
        <select class="form-select form-select-sm w-auto" data-key="kind">${kindOptions}</select>
        <button type="button" class="btn btn-sm btn-outline-danger ms-auto" data-remove
                title="${L.remove}"><i class="fas fa-times"></i></button>
      </div>
      <div class="card-body py-2" data-body></div>`

    card.querySelector('[data-key="kind"]').addEventListener("change", (e) => {
      this.checks[index] = { kind: e.target.value }
      this.applyKindDefaults(this.checks[index])
      this.renderAll(); this.serialize()
    })
    card.querySelector("[data-remove]").addEventListener("click", () => {
      this.checks.splice(index, 1)
      this.renderAll(); this.serialize()
    })

    this.renderBody(card.querySelector("[data-body]"), check, index)
    return card
  }

  renderBody(body, check, index) {
    const L = this.labelsValue.fields
    const row = document.createElement("div")
    row.className = "row g-2 align-items-end"

    const kind = check.kind
    if (kind === "transformation" || kind === "duplication") {
      row.appendChild(this.hostSelect(L.from, check.from, (v) => { check.from = v }))
      row.appendChild(this.hostSelect(L.to, check.to, (v) => { check.to = v }))
    }
    if (kind === "count" || kind === "checksum") {
      row.appendChild(this.hostSelect(L.capture, check.capture, (v) => { check.capture = v }))
    }
    if (kind === "transformation") {
      const layerCol = this.select(L.layer, Object.keys(LAYER_FIELDS), check.layer, (v) => {
        check.layer = v
        check.field = LAYER_FIELDS[v][0]
        this.renderAll(); this.serialize()
      })
      row.appendChild(layerCol)
      row.appendChild(this.select(L.field, LAYER_FIELDS[check.layer] || [], check.field, (v) => { check.field = v }))
    }
    if (kind === "checksum") {
      row.appendChild(this.select(L.layer, CHECKSUM_LAYERS, check.layer, (v) => { check.layer = v }))
    }
    if (KIND_OPS[kind]) {
      const ops = KIND_OPS[kind]
      const opCol = this.select(L.op, ops, check.op, (v) => {
        check.op = v
        if (kind === "transformation") { this.renderAll() }
        this.serialize()
      }, (op) => this.labelsValue.ops[op])
      row.appendChild(opCol)
    }
    const needsValue = (kind === "count" || kind === "duplication" ||
                        (kind === "transformation" && check.op === "equals"))
    if (needsValue) {
      row.appendChild(this.input(L.value, check.value, (v) => { check.value = this.coerce(v) },
                                 kind === "transformation" ? "text" : "number"))
    }

    body.appendChild(row)

    if (kind !== "checksum") {
      body.appendChild(this.filterRow(check))
    }
  }

  filterRow(check) {
    const L = this.labelsValue.fields
    const row = document.createElement("div")
    row.className = "row g-2 align-items-end mt-1"

    const filter = check.filter || {}
    const layers = ["", ...Object.keys(LAYER_FIELDS)]
    const currentLayer = filter.layer || ""
    const fieldKey = Object.keys(filter).find((k) => k !== "layer") || ""

    row.appendChild(this.select(L.filter, layers, currentLayer, (v) => {
      if (v) { check.filter = { layer: v } } else { delete check.filter }
      this.renderAll(); this.serialize()
    }, (l) => (l === "" ? L.no_filter : l)))

    if (currentLayer) {
      row.appendChild(this.select(L.field, LAYER_FIELDS[currentLayer] || [], fieldKey, (v) => {
        check.filter = { layer: currentLayer }
        if (v) check.filter[v] = this.coerce(filter[fieldKey] ?? "")
        this.renderAll(); this.serialize()
      }, undefined, true))
      if (fieldKey) {
        row.appendChild(this.input(L.value, filter[fieldKey], (v) => {
          check.filter[fieldKey] = this.coerce(v)
        }))
      }
    }
    return row
  }

  // ── Small field factories (col-wrapped, serialize on change) ────────────

  col(labelText, el) {
    const col = document.createElement("div")
    col.className = "col-auto"
    const label = document.createElement("label")
    label.className = "form-label small text-muted mb-0"
    label.textContent = labelText
    col.appendChild(label)
    col.appendChild(el)
    return col
  }

  select(labelText, options, current, onChange, optionLabel, includeBlank = false) {
    const sel = document.createElement("select")
    sel.className = "form-select form-select-sm"
    const opts = includeBlank && !options.includes("") ? ["", ...options] : options
    for (const o of opts) {
      const opt = document.createElement("option")
      opt.value = o
      opt.textContent = optionLabel ? optionLabel(o) : o
      if (o === (current ?? "")) opt.selected = true
      sel.appendChild(opt)
    }
    if (current !== undefined && current !== "" && !opts.includes(current)) {
      const opt = document.createElement("option")
      opt.value = opt.textContent = current
      opt.selected = true
      sel.appendChild(opt)
    }
    sel.addEventListener("change", (e) => { onChange(e.target.value); this.serialize() })
    return this.col(labelText, sel)
  }

  // Host selects read the topology builder's current hosts on focus, same
  // trick as traffic_mappings_controller (the builder fires no events).
  hostSelect(labelText, current, onChange) {
    const col = this.select(labelText, this.topologyHosts(), current, onChange)
    const sel = col.querySelector("select")
    sel.addEventListener("focus", () => {
      const value = sel.value
      sel.innerHTML = ""
      for (const h of new Set([...this.topologyHosts(), ...(value ? [value] : [])])) {
        const opt = document.createElement("option")
        opt.value = opt.textContent = h
        if (h === value) opt.selected = true
        sel.appendChild(opt)
      }
    })
    return col
  }

  input(labelText, current, onChange, type = "text") {
    const inp = document.createElement("input")
    inp.type = type
    inp.className = "form-control form-control-sm"
    inp.value = current ?? ""
    inp.addEventListener("input", (e) => { onChange(e.target.value); this.serialize() })
    return this.col(labelText, inp)
  }

  // ── Data plumbing ────────────────────────────────────────────────────────

  addCheck() {
    const check = { kind: "transformation" }
    this.applyKindDefaults(check)
    this.checks.push(check)
    this.renderAll(); this.serialize()
  }

  applyKindDefaults(check) {
    const hosts = this.topologyHosts()
    switch (check.kind) {
      case "transformation":
        Object.assign(check, { from: hosts[0] || "h1", to: hosts[1] || "h2",
                               layer: "ethernet", field: "src_mac", op: "unchanged" })
        break
      case "count":
        Object.assign(check, { capture: hosts[1] || "h2", op: "gte", value: 1 })
        break
      case "checksum":
        Object.assign(check, { capture: hosts[1] || "h2", layer: "ipv4" })
        break
      case "duplication":
        Object.assign(check, { from: hosts[0] || "h1", to: hosts[1] || "h2",
                               op: "lte", value: 1 })
        break
    }
  }

  serialize() {
    this.jsonTarget.value = this.checks.length === 0
      ? ""
      : JSON.stringify({ checks: this.checks }, null, 2)
  }

  coerce(value) {
    return /^-?\d+$/.test(String(value).trim()) ? parseInt(value, 10) : value
  }

  topologyHosts() {
    const field = document.getElementById("topology_json_output")
    if (!field || !field.value) return []
    try {
      return (JSON.parse(field.value).connections || [])
        .map((c) => c.host_name).filter(Boolean)
    } catch { return [] }
  }
}

import { Controller } from "@hotwired/stimulus"
import cytoscape from "cytoscape"

// Read-only network topology graph on the exercise page (Cytoscape).
//
// Replaces the old inline <script> + CDN <script src> pair, which raced
// under Turbo Drive: on Turbo navigations the external script loads
// asynchronously, so the inline init ran before `cytoscape` existed and
// the canvas stayed blank until a hard refresh. As a Stimulus controller
// with the library vendored through the importmap, connect() fires on
// every kind of visit — initial load, Turbo navigation, and back/forward
// cache restores (where inline scripts never re-run at all).
export default class extends Controller {
  static targets = ["canvas", "info"]
  static values = { topo: String, i18n: Object }

  connect() {
    let topo
    try {
      topo = JSON.parse(this.topoValue)
    } catch {
      return
    }

    const I18N = this.i18nValue
    const sw = topo.switch || {}
    const conns = topo.connections || []

    const elements = [{
      data: { id: "__sw__", label: sw.name || "sw1", kind: "switch", raw: JSON.stringify(sw) },
      position: { x: 0, y: 0 },
    }]

    const n = conns.length
    conns.forEach((conn, i) => {
      const angle = (2 * Math.PI * i / Math.max(n, 1)) - Math.PI / 2
      const radius = Math.max(170, n * 60)
      elements.push({
        data: { id: conn.host_name, label: conn.host_name, kind: "host", raw: JSON.stringify(conn) },
        position: { x: Math.round(Math.cos(angle) * radius), y: Math.round(Math.sin(angle) * radius) },
      })
      elements.push({
        data: {
          id: "edge_p" + conn.port, source: conn.host_name, target: "__sw__",
          label: I18N.port + " " + conn.port, raw: JSON.stringify(conn),
        },
      })
    })

    this.cy = cytoscape({
      container: this.canvasTarget,
      elements: elements,

      style: [
        // Switch — blue rectangle (matches P4Docker switch node style)
        {
          selector: 'node[kind="switch"]',
          style: {
            "shape": "rectangle", "width": 130, "height": 60,
            "background-color": "#0d6efd", "border-width": 2, "border-color": "#084298",
            "label": "data(label)", "color": "#ffffff", "font-size": 14,
            "font-weight": "bold", "text-valign": "center", "text-halign": "center",
          },
        },
        // Host — green ellipse (matches P4Docker host node style)
        {
          selector: 'node[kind="host"]',
          style: {
            "shape": "ellipse", "width": 80, "height": 80,
            "background-color": "#198754", "border-width": 2, "border-color": "#0f5132",
            "label": "data(label)", "color": "#ffffff", "font-size": 13,
            "font-weight": "bold", "text-valign": "center", "text-halign": "center",
          },
        },
        // Edges — grey lines with port label
        {
          selector: "edge",
          style: {
            "width": 2, "line-color": "#6c757d", "label": "data(label)",
            "font-size": 11, "color": "#343a40", "text-rotation": "autorotate",
            "text-background-color": "#f0f4f8", "text-background-opacity": 0.95,
            "text-background-padding": "3px", "curve-style": "straight",
            "target-arrow-shape": "none",
          },
        },
        {
          selector: ":selected",
          style: {
            "background-color": "#ffc107", "border-color": "#997404",
            "line-color": "#ffc107", "color": "#000000",
          },
        },
      ],

      layout: { name: "preset" },
      userZoomingEnabled: true,
      userPanningEnabled: true,
      minZoom: 0.25,
      maxZoom: 4,
    })

    this.cy.fit(undefined, 50)
    this.wireInfoPanel(I18N)
  }

  disconnect() {
    this.cy?.destroy()
    this.cy = null
  }

  zoomIn()  { this.cy.zoom(this.cy.zoom() * 1.25); this.cy.center() }
  zoomOut() { this.cy.zoom(this.cy.zoom() / 1.25); this.cy.center() }
  fit()     { this.cy.fit(undefined, 40) }

  wireInfoPanel(I18N) {
    const info = this.infoTarget

    const row = (label, value) => {
      if (!value) return ""
      return '<div class="d-flex justify-content-between border-bottom py-1 gap-2">' +
        '<span class="text-muted text-nowrap">' + label + "</span>" +
        '<code class="text-end" style="word-break:break-all;font-size:0.78rem;">' + value + "</code>" +
        "</div>"
    }
    const section = (title) =>
      '<div class="text-muted small fw-semibold mt-2 mb-1 border-top pt-1">' + title + "</div>"

    this.cy.on("tap", 'node[kind="switch"]', (e) => {
      const d = JSON.parse(e.target.data("raw"))
      info.innerHTML =
        '<strong><i class="fas fa-server me-1" style="color:#0d6efd;"></i>' + (d.name || "sw1") + "</strong>" +
        '<span class="badge bg-primary ms-2 small">' + I18N.p4Switch + "</span>" +
        row(I18N.image, d.image || "ghcr.io/lucastrombet/p4ering/p4d:1.0") +
        row(I18N.thriftPort, String(d.thrift_port || 50001))
    })

    this.cy.on("tap", 'node[kind="host"]', (e) => {
      const c = JSON.parse(e.target.data("raw"))
      info.innerHTML =
        '<strong><i class="fas fa-desktop me-1" style="color:#198754;"></i>' + c.host_name + "</strong>" +
        '<span class="badge bg-success ms-2 small">' + I18N.host + "</span>" +
        row(I18N.image, c.host_image || "") +
        row(I18N.ipCidr, c.host_ip || "") +
        row(I18N.mac, c.host_mac || "") +
        section(I18N.connectedToSwitch) +
        row(I18N.port, String(c.port || "")) +
        row(I18N.swIp, c.sw_ip || "") +
        row(I18N.swMac, c.sw_mac || "")
    })

    this.cy.on("tap", "edge", (e) => {
      const c = JSON.parse(e.target.data("raw"))
      info.innerHTML =
        '<strong><i class="fas fa-ethernet me-1" style="color:#6c757d;"></i>' + I18N.port + " " + c.port + "</strong>" +
        '<span class="badge bg-secondary ms-2 small">' + I18N.link + "</span>" +
        section(I18N.hostSide) +
        row(I18N.ipCidr, c.host_ip || "") +
        row(I18N.mac, c.host_mac || "") +
        section(I18N.switchSide) +
        row(I18N.ipCidr, c.sw_ip || "") +
        row(I18N.mac, c.sw_mac || "") +
        (c.bandwidth ? row(I18N.bandwidth, c.bandwidth) : "") +
        (c.delay ? row(I18N.delay, c.delay) : "")
    })

    this.cy.on("tap", (e) => {
      if (e.target === this.cy) {
        info.innerHTML = '<span class="text-muted">' + I18N.clickHint + "</span>"
      }
    })
  }
}

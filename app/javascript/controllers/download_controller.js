import { Controller } from "@hotwired/stimulus"

// Downloads the text content of another element as a plain-text file.
// Used for the raw tcpdump capture and the BMv2 switch log on the
// submission page — the content is already rendered in the DOM, so no
// extra server round-trip or route is needed.
//
//   <button data-controller="download"
//           data-download-from-value="#some-pre"
//           data-download-filename-value="capture.txt"
//           data-action="download#save">
export default class extends Controller {
  static values = { from: String, filename: String }

  save(event) {
    // The button may live inside a collapse-toggling header (submitted
    // code card) — downloading must not also toggle the collapse.
    event?.stopPropagation()

    const el = document.querySelector(this.fromValue)
    if (!el) return

    const blob = new Blob([el.innerText], { type: "text/plain;charset=utf-8" })
    const url = URL.createObjectURL(blob)
    const a = document.createElement("a")
    a.href = url
    a.download = this.filenameValue || "download.txt"
    document.body.appendChild(a)
    a.click()
    a.remove()
    URL.revokeObjectURL(url)
  }
}

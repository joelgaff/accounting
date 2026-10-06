import { Controller } from "@hotwired/stimulus"

// Turns a <select> into a searchable picker: type a few characters and the
// matching options appear as you go. The select stays in the form (hidden)
// and still carries the value, so nothing server-side changes and a page
// without JavaScript keeps the plain dropdown.
//
// Attached automatically to any select with enough options (see
// application.js); opt out with data-no-combobox.
export default class extends Controller {
  static MAX_SHOWN = 40

  connect() {
    this.select = this.element
    if (this.select.multiple || this.select.dataset.comboboxReady) return
    this.select.dataset.comboboxReady = "1"

    this.options = [...this.select.options]
      .filter(o => o.value !== "")
      .map(o => ({ value: o.value, label: o.text.trim(), haystack: o.text.toLowerCase() }))
    const blank = [...this.select.options].find(o => o.value === "")
    this.allowBlank = !!blank
    this.placeholder = blank ? blank.text.trim() : "Type to search…"

    this.build()
    this.sync()
    this.select.style.display = "none"
  }

  disconnect() {
    this.wrapper?.remove()
    this.list?.remove()
    window.removeEventListener("scroll", this.reposition, true)
    window.removeEventListener("resize", this.reposition)
    this.select.style.display = ""
    delete this.select.dataset.comboboxReady
  }

  place() {
    const r = this.input.getBoundingClientRect()
    const below = window.innerHeight - r.bottom
    const height = Math.min(260, Math.max(120, below - 12))
    this.list.style.left = `${r.left}px`
    this.list.style.width = `${Math.max(r.width, 280)}px`
    this.list.style.maxHeight = `${height}px`
    if (below < 160 && r.top > below) {
      this.list.style.top = ""
      this.list.style.bottom = `${window.innerHeight - r.top + 2}px`
      this.list.style.maxHeight = `${Math.min(260, r.top - 12)}px`
    } else {
      this.list.style.bottom = ""
      this.list.style.top = `${r.bottom + 2}px`
    }
  }

  build() {
    this.wrapper = document.createElement("div")
    this.wrapper.className = "combobox"

    this.input = document.createElement("input")
    this.input.type = "text"
    this.input.className = "combobox-input"
    this.input.autocomplete = "off"
    this.input.spellcheck = false
    this.input.placeholder = this.placeholder
    if (this.select.required) this.input.required = true
    const label = this.select.labels?.[0]
    if (label) this.input.setAttribute("aria-label", label.textContent.trim())
    else if (this.select.getAttribute("aria-label")) this.input.setAttribute("aria-label", this.select.getAttribute("aria-label"))
    this.input.setAttribute("role", "combobox")
    this.input.setAttribute("aria-expanded", "false")

    // The list is fixed-positioned and appended to the body so no table,
    // scroll box or rounded panel with overflow clipping can hide it.
    this.list = document.createElement("ul")
    this.list.className = "combobox-list"
    this.list.hidden = true
    this.list.setAttribute("role", "listbox")

    this.wrapper.append(this.input)
    this.select.insertAdjacentElement("afterend", this.wrapper)
    document.body.append(this.list)
    this.reposition = () => { if (!this.list.hidden) this.place() }
    window.addEventListener("scroll", this.reposition, true)
    window.addEventListener("resize", this.reposition)

    this.input.addEventListener("input", () => this.open(this.input.value))
    this.input.addEventListener("focus", () => { this.input.select(); this.open("") })
    this.input.addEventListener("keydown", e => this.keydown(e))
    this.input.addEventListener("blur", () => setTimeout(() => this.commit(), 120))
    this.list.addEventListener("mousedown", e => {
      const li = e.target.closest("li[data-value]")
      if (li) { e.preventDefault(); this.choose(li.dataset.value) }
    })
  }

  // Show the current selection's label in the box.
  sync() {
    const current = this.options.find(o => o.value === this.select.value)
    this.input.value = current ? current.label : ""
  }

  open(query) {
    const tokens = query.toLowerCase().split(/\s+/).filter(Boolean)
    let matches = tokens.length
      ? this.options.filter(o => tokens.every(t => o.haystack.includes(t)))
      : this.options
    if (tokens.length) {
      const first = tokens[0]
      matches = matches.sort((a, b) => this.rank(a, first) - this.rank(b, first))
    }
    this.matches = matches.slice(0, this.constructor.MAX_SHOWN)
    this.active = this.matches.length ? 0 : -1
    this.render(tokens, matches.length)
  }

  // Code or name starting with the query outranks a match in the middle.
  rank(option, token) {
    const h = option.haystack
    if (h.startsWith(token)) return 0
    if (h.includes("— " + token) || h.includes(" " + token)) return 1
    return 2
  }

  render(tokens, total) {
    this.list.innerHTML = ""
    if (!this.matches.length) {
      const li = document.createElement("li")
      li.className = "combobox-empty"
      li.textContent = "No matches"
      this.list.append(li)
    }
    this.matches.forEach((o, i) => {
      const li = document.createElement("li")
      li.dataset.value = o.value
      li.setAttribute("role", "option")
      li.className = i === this.active ? "is-active" : ""
      li.innerHTML = this.highlight(o.label, tokens)
      this.list.append(li)
    })
    if (total > this.matches.length) {
      const li = document.createElement("li")
      li.className = "combobox-empty"
      li.textContent = `${total - this.matches.length} more… keep typing`
      this.list.append(li)
    }
    this.list.hidden = false
    this.place()
    this.input.setAttribute("aria-expanded", "true")
  }

  highlight(label, tokens) {
    let html = label.replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]))
    tokens.forEach(t => {
      const safe = t.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
      html = html.replace(new RegExp(safe, "ig"), m => `<mark>${m}</mark>`)
    })
    return html
  }

  keydown(e) {
    if (this.list.hidden && ["ArrowDown", "ArrowUp"].includes(e.key)) { this.open(this.input.value); e.preventDefault(); return }
    switch (e.key) {
      case "ArrowDown": e.preventDefault(); this.move(1); break
      case "ArrowUp":   e.preventDefault(); this.move(-1); break
      case "Enter":
        if (!this.list.hidden && this.active >= 0) { e.preventDefault(); this.choose(this.matches[this.active].value) }
        break
      case "Escape": this.close(); this.sync(); break
      case "Tab": if (!this.list.hidden && this.active >= 0 && this.input.value !== "") this.choose(this.matches[this.active].value); break
    }
  }

  move(delta) {
    if (!this.matches.length) return
    this.active = (this.active + delta + this.matches.length) % this.matches.length
    this.list.querySelectorAll("li[data-value]").forEach((li, i) => li.classList.toggle("is-active", i === this.active))
    this.list.querySelector("li.is-active")?.scrollIntoView({ block: "nearest" })
  }

  choose(value) {
    if (this.select.value !== value) {
      this.select.value = value
      this.select.dispatchEvent(new Event("change", { bubbles: true }))
    }
    this.sync()
    this.close()
  }

  // Leaving the box: an exact label keeps, an empty box clears when allowed,
  // anything else snaps back to what was selected.
  commit() {
    const typed = this.input.value.trim().toLowerCase()
    const exact = this.options.find(o => o.haystack === typed)
    if (exact) this.choose(exact.value)
    else if (typed === "" && this.allowBlank) this.choose("")
    else if (typed === "" && !this.select.value) this.close()
    else { this.sync(); this.close() }
  }

  close() {
    this.list.hidden = true
    this.input.setAttribute("aria-expanded", "false")
  }
}

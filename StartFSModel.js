// What `startfs status` prints, as an object, and the words the window uses for it. Pure functions, so `node --test` can run them.

.pragma library

// "10.0 GiB" -> bytes; null when it is not a size.
function bytes(text) {
  var m = /^([0-9.]+)\s*(B|KiB|MiB|GiB|TiB)$/.exec(String(text).trim())
  if (!m) return null
  var unit = { B: 1, KiB: 1024, MiB: 1048576, GiB: 1073741824, TiB: 1099511627776 }
  return parseFloat(m[1]) * unit[m[2]]
}

// 1234567 -> "1.2 MiB", the way `startfs status` writes sizes.
function formatBytes(n) {
  var units = ["B", "KiB", "MiB", "GiB", "TiB"]
  var v = Number(n)
  var i = 0
  while (v >= 1024 && i < units.length - 1) { v /= 1024; i++ }
  return (i === 0 ? String(v) : v.toFixed(1)) + " " + units[i]
}

function emptyStatus() {
  return { data: "", fs: "", copies: 0, node: "", stored: "", offered: "", possible: 0, wanted: 0, nodes: 0,
           usable: "", cache: "", members: [], scrub: "", warnings: [], conflicts: [], repair: null, unreplicated: 0,
           staging: "", ok: false }
}

// `startfs status --json`. The names of the fields are the daemon's (crates/startfs-core/src/control.rs).
function fromJson(j) {
  var out = emptyStatus()
  if (!j.filesystem) return out
  out.data = String(j.verdict || "").toUpperCase()
  out.fs = j.filesystem.name
  out.copies = j.filesystem.copies
  out.wanted = j.filesystem.copies
  out.node = String(j.node_state || "").toLowerCase()
  out.stored = formatBytes(j.usage.stored_bytes)
  out.offered = formatBytes(j.usage.offer_bytes)
  out.possible = j.copies_possible
  out.nodes = j.nodes
  out.usable = formatBytes(j.usable_bytes)
  out.cache = formatBytes(j.cache.used_bytes) + " used of " + formatBytes(j.cache.capacity_bytes)
  out.scrub = String(j.scrub.state || "").replace(/([a-z])([A-Z])/g, "$1 $2").toLowerCase()
  out.members = j.members.map(function (m) {
    return { id: String(m.id), address: m.addr, host: m.addr.replace(/:\d+$/, "").split(".")[0],
             state: String(m.state).toLowerCase() === "online" ? "up" : String(m.state).toLowerCase(),
             offered: formatBytes(m.offer_bytes), self: !!m.is_self, problem: m.problem || "" }
  })
  out.warnings = j.warnings || []
  out.conflicts = (j.conflicts || []).map(function (c) { return c.path })
  out.repair = j.repair ? { atRisk: j.repair.at_risk, degraded: j.repair.degraded } : null
  out.unreplicated = (j.unreplicated || []).reduce(function (n, f) { return n + f.chunks }, 0)
  out.staging = j.staging && j.staging.chunks > 0 ? formatBytes(j.staging.bytes) + " in " + j.staging.chunks + " chunks" : ""
  out.ok = out.data !== ""
  return out
}

function parseStatus(text) {
  var t = String(text).trim()
  if (t.charAt(0) === "{") {
    try { return fromJson(JSON.parse(t)) } catch (e) { return emptyStatus() }
  }
  return fromText(text)
}

// The text of builds that have no --json.
function fromText(text) {
  var out = { data: "", fs: "", copies: 0, node: "", stored: "", offered: "", possible: 0, wanted: 0, nodes: 0,
              usable: "", cache: "", members: [], scrub: "", warnings: [], conflicts: [], repair: null, unreplicated: 0,
              staging: "", ok: false }
  var inMembers = false
  String(text).split("\n").forEach(function (line) {
    var m
    if (inMembers && (m = /^\s+(\d+)\s+(\S+)\s+(up|down|\S+)\s+([0-9.]+ \S+) offered(\s+\(this node\))?\s*$/.exec(line))) {
      out.members.push({ id: m[1], address: m[2], host: m[2].replace(/:\d+$/, "").split(".")[0], state: m[3],
                         offered: m[4], self: !!m[5], problem: "" })
      return
    }
    inMembers = false
    if ((m = /^data: (.+)$/.exec(line))) out.data = m[1].trim()
    else if ((m = /^filesystem: (\S+) \((\d+) copies?\)/.exec(line))) { out.fs = m[1]; out.copies = parseInt(m[2], 10) }
    else if ((m = /^node: (.+)$/.exec(line))) out.node = m[1].trim()
    else if ((m = /^usage: (.+?) stored in .*?, (.+) offered/.exec(line))) { out.stored = m[1]; out.offered = m[2] }
    else if ((m = /^redundancy: (\d+) of (\d+) copies possible \((\d+) nodes?\)/.exec(line))) {
      out.possible = parseInt(m[1], 10); out.wanted = parseInt(m[2], 10); out.nodes = parseInt(m[3], 10)
    }
    else if ((m = /^usable: (?:about )?(.+)$/.exec(line))) out.usable = m[1].trim()
    else if ((m = /^cache: (.+)$/.exec(line))) out.cache = m[1].trim()
    else if ((m = /^scrub: (.+)$/.exec(line))) out.scrub = m[1].trim()
    else if (/^members:/.test(line)) inMembers = true
    else if (/^warning/i.test(line)) out.warnings.push(line.replace(/^warnings?:\s*/i, "").trim())
  })
  out.ok = out.data !== ""
  return out
}

// "safe" | "degraded" | "unknown": what the bar icon draws and the header colours itself by.
function health(s) {
  if (!s || !s.ok) return "unknown"
  if (s.data.toUpperCase() === "SAFE" && s.possible >= s.wanted && s.warnings.length === 0) return "safe"
  return "degraded"
}

function headline(s) {
  if (!s || !s.ok) return "Cannot reach the StartFS daemon"
  if (s.data.toUpperCase() !== "SAFE") return "Data is " + s.data.toLowerCase()
  if (s.possible < s.wanted) return "Only " + s.possible + " of " + s.wanted + " copies possible"
  if (s.repair) return "Safe, repairing " + (s.repair.atRisk + s.repair.degraded) + " chunks"
  return "Your data is safe"
}

// Same grammar as `startfs config --offer`, checked before it is sent.
function validSize(text) { return /^([0-9]+|[0-9]+(\.[0-9]+)?[KMGT]i?B?)$/.test(String(text).trim()) }


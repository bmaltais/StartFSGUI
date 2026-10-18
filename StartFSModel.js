// What `startfs status` prints, as an object, and the words the window uses for it. Pure functions, so `node --test` can run them.

.pragma library

// "10.0 GiB" -> bytes; null when it is not a size.
function bytes(text) {
  var m = /^([0-9.]+)\s*(B|KiB|MiB|GiB|TiB)$/.exec(String(text).trim())
  if (!m) return null
  var unit = { B: 1, KiB: 1024, MiB: 1048576, GiB: 1073741824, TiB: 1099511627776 }
  return parseFloat(m[1]) * unit[m[2]]
}

function parseStatus(text) {
  var out = { data: "", fs: "", copies: 0, node: "", stored: "", offered: "", possible: 0, wanted: 0, nodes: 0,
              usable: "", cache: "", members: [], scrub: "", warnings: [], ok: false }
  var inMembers = false
  String(text).split("\n").forEach(function (line) {
    var m
    if (inMembers && (m = /^\s+(\d+)\s+(\S+)\s+(up|down|\S+)\s+([0-9.]+ \S+) offered(\s+\(this node\))?\s*$/.exec(line))) {
      out.members.push({ id: m[1], address: m[2], host: m[2].replace(/:\d+$/, "").split(".")[0], state: m[3],
                         offered: m[4], self: !!m[5] })
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
  return "Your data is safe"
}

// Same grammar as `startfs config --offer`, checked before it is sent.
function validSize(text) { return /^([0-9]+|[0-9]+(\.[0-9]+)?[KMGT]i?B?)$/.test(String(text).trim()) }


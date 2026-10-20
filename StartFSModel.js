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

// What a size box shows for a number of bytes, in the grammar `startfs config` reads back: "100G", "512M", "0".
function sizeInput(n) {
  var v = Number(n) || 0
  if (v === 0) return "0"
  var units = ["", "K", "M", "G", "T"]
  var i = 0
  while (v >= 1024 && v % 1024 === 0 && i < units.length - 1) { v /= 1024; i++ }
  return String(v) + units[i]
}

// "1.4x", or "" when there is nothing to compare with.
function ratioText(a, b) { return b > 0 ? (a / b).toFixed(1) + "x" : "" }

// 75 -> "1 min", 7300 -> "2 h": how long ago, or how long left, in the fewest words.
function durationText(secs) {
  var s = Math.max(0, Math.round(Number(secs) || 0))
  if (s < 60) return s + " s"
  if (s < 3600) return Math.round(s / 60) + " min"
  if (s < 172800) return Math.round(s / 3600) + " h"
  return Math.round(s / 86400) + " days"
}

// Round-trip time in microseconds -> "5.2 ms".
function rttText(micros) {
  if (micros === null || micros === undefined) return ""
  var ms = micros / 1000
  return (ms < 10 ? ms.toFixed(1) : String(Math.round(ms))) + " ms"
}

// "v1.10.2" < "v1.10.10": -1, 0 or 1. Anything that is not a release sorts first.
function compareRelease(a, b) {
  function parts(v) { var m = /^v?(\d+)\.(\d+)\.(\d+)/.exec(String(v || "")); return m ? [+m[1], +m[2], +m[3]] : [-1, -1, -1] }
  var x = parts(a), y = parts(b)
  for (var i = 0; i < 3; i++) if (x[i] !== y[i]) return x[i] < y[i] ? -1 : 1
  return 0
}

function emptyStatus() {
  return { data: "", verdict: "", fs: "", copies: 0, node: "", stored: "", offered: "", possible: 0, wanted: 0, nodes: 0,
           usable: "", cache: "", members: [], scrub: "", warnings: [], conflicts: [], repair: null, unreplicated: 0,
           staging: "", storage: null, ok: false, json: false, upgrade: null, stopping: false, rechecking: 0,
           stranded: [], unheard: [], tickBusy: null, gc: null, scrubInfo: null, log: null, filesystem: null,
           usage: null, cacheInfo: null }
}

// Where the space went (`efficiency` of status --json, from builds that report it): null when it is not there or there are no
// files yet. `copies` turns this node's plaintext into its share of what the cluster should hold.
function storageOf(e, copies) {
  if (!e || !(e.logical_bytes > 0)) return null
  var after = e.referenced_bytes + (e.inline_bytes || 0)
  var expected = e.referenced_bytes * copies
  return {
    files: formatBytes(e.logical_bytes),
    afterDedup: formatBytes(after),
    dedup: ratioText(e.logical_bytes, after),
    nodeDisk: formatBytes(e.local_disk_bytes),
    compression: ratioText(e.local_plain_bytes, e.local_disk_bytes),
    share: expected > 0 ? (100 * e.local_plain_bytes / expected).toFixed(1) + "%" : "",
    expected: formatBytes(expected),
    zstdChunks: e.zstd_chunks || 0,
    rawChunks: e.raw_chunks || 0
  }
}

// `startfs stats --json` (one report per member, from builds that have it) as host -> what the member's row shows.
// A member that did not answer has answered: false.
function parseNodeStats(text, copies) {
  var rows
  try { rows = JSON.parse(String(text)) } catch (e) { return ({}) }
  if (!Array.isArray(rows)) return ({})
  var referenced = 0
  rows.forEach(function (r) { if (!referenced && r.stats) referenced = r.stats.efficiency.referenced_bytes })
  var expected = referenced * copies
  var out = ({})
  rows.forEach(function (r) {
    var host = hostOf(r.addr)
    if (!r.stats) { out[host] = { answered: false }; return }
    var s = r.stats
    out[host] = {
      answered: true,
      disk: formatBytes(s.usage.stored_bytes),
      diskBytes: s.usage.stored_bytes,
      offered: formatBytes(s.usage.offer_bytes),
      offerBytes: s.usage.offer_bytes,
      chunks: s.usage.chunks,
      compression: ratioText(s.efficiency.local_plain_bytes, s.efficiency.local_disk_bytes),
      share: expected > 0 ? (100 * s.efficiency.local_plain_bytes / expected).toFixed(1) + "%" : "",
      garbage: s.pending_gc_bytes > 0 ? formatBytes(s.pending_gc_bytes) : ""
    }
  })
  return out
}

// "mini2.taild10b64.ts.net:7600" -> "mini2": the name rows show, and the one ssh is given.
function hostOf(addr) { return String(addr).replace(/:\d+$/, "").split(".")[0] }

// The daemon's member states, in the window's words. Unknown (the daemon restarted and has not heard from it yet) and
// upgrading (paused for a restart it announced) are expected, so they are not drawn as trouble.
var STATES = { online: "up", down: "down", lost: "lost", leaving: "leaving", upgrading: "upgrading", unknown: "unknown" }
function stateOf(raw) { var s = String(raw || "").toLowerCase(); return STATES[s] || s }

// A member's upgrade step: "" | "staging" | "staged" | "waiting on mount" | "restarting" | "failed".
function upgradeStepOf(p) {
  if (p === null || p === undefined) return { step: "", why: "" }
  if (typeof p === "object" && p.Failed !== undefined) return { step: "failed", why: String(p.Failed) }
  var s = String(p)
  return { step: s === "WaitingOnMount" ? "waiting on mount" : s.toLowerCase(), why: "" }
}

function memberOf(m) {
  var up = upgradeStepOf(m.upgrade)
  return {
    id: String(m.id), address: m.addr, host: hostOf(m.addr), fqdn: String(m.addr).replace(/:\d+$/, ""),
    state: stateOf(m.state), offered: formatBytes(m.offer_bytes), offerBytes: m.offer_bytes || 0,
    weightBytes: m.weight_bytes || 0, site: m.site || "", self: !!m.is_self, problem: m.problem || "",
    rtt: rttText(m.rtt_micros), release: m.release || "", protocol: m.protocol === undefined ? null : m.protocol,
    upgradeStep: up.step, upgradeWhy: up.why,
    lastSeen: m.last_seen ? { secs: m.last_seen.secs_ago, exact: !!m.last_seen.exact } : null,
    behind: m.behind ? { tickSecs: m.behind.tick_secs_ago, messages: m.behind.inbox_messages, bytes: m.behind.inbox_bytes } : null,
    standinSecs: m.standin_secs_left === undefined ? null : m.standin_secs_left
  }
}

// `startfs status --json`. The names of the fields are the daemon's (crates/startfs-core/src/control.rs).
function fromJson(j) {
  var out = emptyStatus()
  out.json = true
  out.stopping = !!j.stopping
  if (!j.filesystem) return out
  out.verdict = String(j.verdict || "")
  out.data = verdictWord(out.verdict)
  out.filesystem = j.filesystem
  out.fs = j.filesystem.name
  out.copies = j.filesystem.copies
  out.wanted = j.filesystem.copies
  out.node = stateOf(j.node_state)
  out.usage = j.usage
  out.stored = formatBytes(j.usage.stored_bytes)
  out.offered = formatBytes(j.usage.offer_bytes)
  out.possible = j.copies_possible
  out.nodes = j.nodes
  out.usable = formatBytes(j.usable_bytes)
  out.cacheInfo = j.cache
  out.cache = formatBytes(j.cache.used_bytes) + " used of " + formatBytes(j.cache.capacity_bytes)
  out.scrubInfo = j.scrub
  out.scrub = String(j.scrub.state || "").replace(/([a-z])([A-Z])/g, "$1 $2").toLowerCase()
  out.members = j.members.map(memberOf)
  out.warnings = j.warnings || []
  out.conflicts = (j.conflicts || []).map(function (c) { return c.path })
  out.repair = j.repair ? { atRisk: j.repair.at_risk, degraded: j.repair.degraded } : null
  out.unreplicated = (j.unreplicated || []).reduce(function (n, f) { return n + f.chunks }, 0)
  out.staging = j.staging && j.staging.chunks > 0 ? formatBytes(j.staging.bytes) + " in " + j.staging.chunks + " chunks" : ""
  out.storage = storageOf(j.efficiency, j.filesystem.copies)
  out.upgrade = j.upgrade ? { release: j.upgrade.release, lockstep: j.upgrade.lockstep, go: !!j.upgrade.go,
                              complete: !!j.upgrade.complete, split: j.upgrade.split || [] } : null
  out.rechecking = j.rechecking || 0
  out.stranded = j.stranded || []
  out.unheard = j.unheard || []
  out.tickBusy = j.tick_busy || null
  out.gc = j.gc || null
  out.log = j.log || null
  out.ok = out.data !== ""
  return out
}

// "AtRisk" -> "AT RISK", as the text form says it.
function verdictWord(v) {
  return ({ Safe: "SAFE", Degraded: "DEGRADED", AtRisk: "AT RISK", BestEffort: "BEST-EFFORT" })[v] || String(v || "").toUpperCase()
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
  var out = emptyStatus()
  var inMembers = false
  String(text).split("\n").forEach(function (line) {
    var m
    if (inMembers && (m = /^\s+(\d+)\s+(\S+)\s+(up|down|\S+)\s+([0-9.]+ \S+) offered(\s+\(this node\))?\s*$/.exec(line))) {
      out.members.push(memberOf({ id: m[1], addr: m[2], state: m[3] === "up" ? "Online" : m[3], offer_bytes: bytes(m[4]),
                                  is_self: !!m[5] }))
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
  if (!s || !s.ok) return s && s.stopping ? "The daemon is restarting" : "Cannot reach the StartFS daemon"
  var d = s.data.toUpperCase()
  if (d === "AT RISK") return "Some data has a single copy"
  if (d === "BEST-EFFORT") return "Fewer nodes than copies wanted"
  if (d !== "SAFE") {
    if (s.repair) return "Repairing " + (s.repair.atRisk + s.repair.degraded) + " chunks"
    return "Data is " + s.data.toLowerCase()
  }
  if (s.possible < s.wanted) return "Only " + s.possible + " of " + s.wanted + " copies possible"
  return "Your data is safe"
}

// One line under the headline: what keeps it safe.
function summary(s) {
  if (!s || !s.ok) return "Start it with: systemctl --user start startfs"
  var p = [s.possible + " of " + s.wanted + " copies", s.usable + " usable"]
  if (s.storage) p.push(s.storage.files + " in files")
  if (s.rechecking > 0) p.push("re-checking " + s.rechecking + " chunks")
  return p.join("  ·  ")
}

// The release most members run: what "the cluster's release" means in the header.
function clusterRelease(s) {
  var count = {}
  var best = ""
  ;(s.members || []).forEach(function (m) {
    if (!m.release) return
    count[m.release] = (count[m.release] || 0) + 1
    if (best === "" || count[m.release] > count[best]) best = m.release
  })
  return best
}

// Where a cluster upgrade is: null when none is running, else { target, done, total, lockstep, waiting, failed, text }.
// It is running while a member has a step to take (staging, staged, waiting, restarting, failed). A member that merely lags a
// release with nothing to do is not an upgrade: the Upgrade page says it, and the header offers to bring it up.
// Members that are down or lost are not counted: they catch up when they return.
function upgradeProgress(s) {
  if (!s || !s.upgrade) return null
  var u = s.upgrade
  var members = (s.members || []).filter(function (m) { return m.state !== "lost" && m.state !== "down" })
  if (!members.some(function (m) { return m.upgradeStep !== "" })) return null
  var done = members.filter(function (m) { return m.upgradeStep === "" && compareRelease(m.release, u.release) >= 0 }).length
  var waiting = members.filter(function (m) { return m.upgradeStep === "waiting on mount" })
  var failed = members.filter(function (m) { return m.upgradeStep === "failed" })
  var how = u.lockstep === true ? "every node swaps together" : "one node at a time"
  var text = failed.length ? "Upgrade stopped: " + failed[0].host + " failed"
    : waiting.length ? waiting.map(function (m) { return m.host }).join(", ") + " waits for its mount to be free"
    : "Moving to " + u.release + ", " + how
  return { target: u.release, done: done, total: members.length, lockstep: u.lockstep === true,
           waiting: waiting, failed: failed, text: text }
}

// A member's state, in one or two words, for its tag and its details.
function stateText(m) {
  switch (m.state) {
  case "up": return "Up"
  case "down": return "Down"
  case "lost": return "Lost"
  case "leaving": return "Leaving"
  case "upgrading": return "Restarting for an upgrade"
  case "unknown": return "Not heard from yet"
  }
  return m.state
}
// "bad" | "warn" | "ok" | "quiet": how loudly a member's state is drawn.
function stateTone(m) {
  if (m.upgradeStep === "failed") return "bad"
  if (m.state === "down" || m.state === "lost") return "bad"
  if (m.behind || m.upgradeStep === "waiting on mount") return "warn"
  if (m.state === "up") return "ok"
  return "quiet"
}

// Whether a step is the moment to watch (drawn in the accent): downloading or restarting, not waiting.
function stepActive(m) { return m.upgradeStep === "staging" || m.upgradeStep === "restarting" }

// What the upgrade step says, as a phrase.
function stepText(m, target) {
  switch (m.upgradeStep) {
  case "staging": return "downloading " + (target || "the new release")
  case "staged": return (target || "new release") + " staged, waiting its turn"
  case "waiting on mount": return "waiting for its mount"
  case "restarting": return "restarting on " + (target || "the new release")
  case "failed": return "upgrade failed" + (m.upgradeWhy ? ": " + m.upgradeWhy : "")
  }
  return ""
}

// The status line of a member's row: its release, its space, how far it is. `n` is its `stats` figures, if read.
function memberLine(m, n, target) {
  var step = stepText(m, target)
  if (m.state === "down" || m.state === "lost") {
    var seen = m.lastSeen ? "last seen " + (m.lastSeen.exact ? "" : "over ") + durationText(m.lastSeen.secs) + " ago" : "not reachable"
    return [seen, m.problem].filter(function (p) { return p !== "" }).join("  ·  ")
  }
  if (m.state === "leaving") return "handing its data to the others"
  if (m.state === "unknown") return "not heard from since this node restarted"
  var parts = []
  if (step !== "") parts.push(step)
  else if (m.release !== "") parts.push(m.release)
  if (n && n.answered) parts.push(n.disk + " of " + n.offered)
  else parts.push(m.offered + " offered")
  // During an upgrade step the line is about the step; the round trip can wait.
  if (m.rtt !== "" && step === "") parts.push(m.rtt)
  if (m.behind) parts.push(durationText(m.behind.tickSecs) + " behind")
  return parts.join("  ·  ")
}

// 0..1, how full a member's offer is; -1 when not known.
function fill(m, n) {
  if (!n || !n.answered || !(n.offerBytes > 0)) return -1
  return Math.min(1, n.diskBytes / n.offerBytes)
}

// Same grammar as `startfs config --offer`: a whole number with an optional K, M, G or T (B, KB, KiB... too), no decimals.
function validSize(text) { return /^[0-9]+([KMGT](i?B)?|B)?$/i.test(String(text).trim()) }
// A site name `startfsgui set site` accepts; empty clears it.
function validSite(text) { return /^[A-Za-z0-9._-]{0,64}$/.test(String(text).trim()) }

// `startfs activity --json` -> what the Activity page lists. Rates are per second over the counters' window.
function parseActivity(text) {
  var a
  try { a = JSON.parse(String(text)) } catch (e) { return null }
  if (!a || typeof a !== "object") return null
  var w = a.window_secs > 0 ? a.window_secs : 60
  function sum(c) { return c ? c.chunk.bytes + c.metadata.bytes + c.gossip.bytes + c.other.bytes : 0 }
  var sent = 0, received = 0, timedOut = 0, retried = 0, inFlight = 0
  var peers = (a.peers || []).map(function (p) {
    var t = p.traffic
    var s = t ? sum(t.sent) : 0, r = t ? sum(t.received) : 0
    sent += s; received += r; inFlight += p.in_flight || 0
    if (t) { timedOut += t.timed_out || 0; retried += t.retried || 0 }
    return { host: hostOf(p.addr), state: stateOf(p.state), out: formatBytes(s / w) + "/s", in: formatBytes(r / w) + "/s",
             inFlight: p.in_flight || 0, hasTraffic: !!t }
  })
  var res = a.resources || {}
  function psi(x) { return x ? x.avg10.toFixed(1) + "% now, " + x.avg60.toFixed(1) + "% over a minute" : "not available" }
  return {
    enabled: !!a.enabled,
    window: Math.round(w),
    out: formatBytes(sent / w) + "/s",
    in: formatBytes(received / w) + "/s",
    inFlight: inFlight, timedOut: timedOut, retried: retried,
    peers: peers,
    tick: a.tick ? Math.round(a.tick.busy_fraction * 100) + "% busy, " + a.tick.avg_ms.toFixed(1) + " ms on average, "
                   + Math.round(a.tick.max_ms) + " ms at most" : "",
    queue: a.queue ? (a.queue.chunks === 0 ? "empty" : a.queue.chunks + " chunks"
                      + (a.queue.oldest_secs !== null ? ", oldest " + durationText(a.queue.oldest_secs) : "")) : "",
    memory: res.rss_bytes !== null && res.rss_bytes !== undefined ? formatBytes(res.rss_bytes) : "not available",
    cpu: res.cpu_secs !== null && res.cpu_secs !== undefined ? Math.round(res.cpu_secs) + " s of CPU since it started" : "not available",
    threads: res.threads || 0,
    cpuPressure: psi(res.cpu_pressure), memoryPressure: psi(res.memory_pressure), ioPressure: psi(res.io_pressure),
    written: res.written_bytes !== null && res.written_bytes !== undefined ? formatBytes(res.written_bytes) : "not available",
    readCache: a.structures && a.structures.decoded_cache
      ? formatBytes(a.structures.decoded_cache.bytes || 0) + " of " + formatBytes(a.structures.decoded_cache.limit_bytes || 0) : ""
  }
}

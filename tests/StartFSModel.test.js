const test = require("node:test")
const assert = require("node:assert")
const fs = require("node:fs")
const path = require("node:path")

// StartFSModel.js is a QML library; load it as a plain script.
const source = fs.readFileSync(path.join(__dirname, "..", "StartFSModel.js"), "utf8").replace(/^\.pragma.*$/m, "")
const M = new Function(source + "\nreturn { bytes, formatBytes, parseStatus, parseNodeStats, health, headline, validSize, validSite, sizeInput, compareRelease, clusterRelease, upgradeProgress, memberLine, stateTone, parseActivity, rttText, durationText }")()

const REAL = `data: SAFE
filesystem: home (3 copies)
node: online
usage: 10.4 MiB stored in 169 chunks, 10.0 GiB offered
redundancy: 3 of 3 copies possible (6 nodes)
usable: about 140.0 GiB
cache: 2.7 MiB used of 1.0 GiB
members:
  0         mini2.taild10b64.ts.net:7600    up   10.0 GiB offered
  1         3090.taild10b64.ts.net:7600     up   10.0 GiB offered  (this node)
  15728640  vps1.taild10b64.ts.net:7600     up  100.0 GiB offered
scrub: idle
metadata log: 1 entries, 6720 objects
`

test("parses a real status", () => {
  const s = M.parseStatus(REAL)
  assert.strictEqual(s.fs, "home")
  assert.strictEqual(s.copies, 3)
  assert.strictEqual(s.offered, "10.0 GiB")
  assert.strictEqual(s.possible, 3)
  assert.strictEqual(s.nodes, 6)
  assert.strictEqual(s.members.length, 3)
  assert.strictEqual(s.members[1].self, true)
  assert.strictEqual(s.members[1].host, "3090")
  assert.strictEqual(M.health(s), "safe")
})

test("fewer copies possible than wanted is degraded", () => {
  const s = M.parseStatus(REAL.replace("3 of 3 copies", "2 of 3 copies"))
  assert.strictEqual(M.health(s), "degraded")
  assert.strictEqual(M.headline(s), "Only 2 of 3 copies possible")
})

test("empty output is unknown", () => {
  const s = M.parseStatus("")
  assert.strictEqual(M.health(s), "unknown")
})

test("size grammar", () => {
  for (const ok of ["0", "500M", "10G", "2T", "10GiB", "10gb", "512B"]) assert.ok(M.validSize(ok), ok)
  // startfs config reads whole numbers only since 1.5.9.
  for (const bad of ["", "G", "10 G", "-1", "10X", "1.5GiB"]) assert.ok(!M.validSize(bad), bad)
})

test("bytes", () => { assert.strictEqual(M.bytes("1.0 GiB"), 1073741824); assert.strictEqual(M.bytes("x"), null) })

const JSON_STATUS = JSON.stringify({
  verdict: "Safe", filesystem: { name: "home", copies: 3 }, node_state: "Online",
  usage: { chunks: 675, stored_bytes: 53624830, offer_bytes: 10737418240 }, staging: { chunks: 0, bytes: 0 },
  cache: { chunks: 100, used_bytes: 2909931, capacity_bytes: 1073741824 },
  members: [
    { id: 0, addr: "mini2.taild10b64.ts.net:7600", state: "Online", offer_bytes: 10737418240, is_self: false, problem: null },
    { id: 1, addr: "3090.taild10b64.ts.net:7600", state: "Online", offer_bytes: 10737418240, is_self: true, problem: null },
    { id: 2, addr: "vps1.taild10b64.ts.net:7600", state: "Down", offer_bytes: 107374182400, is_self: false, problem: "timed out" }
  ],
  nodes: 3, copies_possible: 3, usable_bytes: 150323855360, unreplicated: [{ chunks: 4 }], repair: null, unheard: [],
  scrub: { state: "PausedOnBattery" }, warnings: [], conflicts: [{ path: "/a/b (conflict)" }]
})

test("parses status --json into the same shape as the text", () => {
  const s = M.parseStatus(JSON_STATUS)
  assert.strictEqual(s.ok, true)
  assert.strictEqual(s.data, "SAFE")
  assert.strictEqual(s.fs, "home")
  assert.strictEqual(s.offered, "10.0 GiB")
  assert.strictEqual(s.stored, "51.1 MiB")
  assert.strictEqual(s.usable, "140.0 GiB")
  assert.strictEqual(s.cache, "2.8 MiB used of 1.0 GiB")
  assert.strictEqual(s.scrub, "paused on battery")
  assert.strictEqual(s.members[1].self, true)
  assert.strictEqual(s.members[1].host, "3090")
  assert.strictEqual(s.members[2].state, "down")
  assert.strictEqual(s.members[2].problem, "timed out")
  assert.strictEqual(s.unreplicated, 4)
  assert.deepStrictEqual(s.conflicts, ["/a/b (conflict)"])
  assert.strictEqual(M.health(s), "safe")
})

test("repair shows in the headline", () => {
  const j = JSON.parse(JSON_STATUS)
  j.verdict = "Degraded"
  j.repair = { at_risk: 1, degraded: 2 }
  assert.strictEqual(M.headline(M.parseStatus(JSON.stringify(j))), "Repairing 3 chunks")
})

test("no filesystem or broken JSON is unknown", () => {
  assert.strictEqual(M.health(M.parseStatus('{"filesystem":null}')), "unknown")
  assert.strictEqual(M.health(M.parseStatus("{oops")), "unknown")
})

// The two fixtures are what the storage-efficiency build printed from a throwaway daemon with no files yet.
const GiB = 1073741824
const withFiles = (fixture) => {
  const j = JSON.parse(fs.readFileSync(path.join(__dirname, fixture), "utf8"))
  return j
}

test("a build that reports efficiency but has no files yet shows no storage block", () => {
  const s = M.parseStatus(fs.readFileSync(path.join(__dirname, "fixture-status-1.0.8.json"), "utf8"))
  assert.strictEqual(s.ok, true)
  assert.strictEqual(s.storage, null)
})

test("efficiency becomes the storage block", () => {
  const j = withFiles("fixture-status-1.0.8.json")
  j.efficiency = { logical_bytes: 12 * GiB, referenced_bytes: 6 * GiB, inline_bytes: 0, local_plain_bytes: 3 * GiB,
                   local_disk_bytes: 2 * GiB, raw_chunks: 10, zstd_chunks: 90 }
  const s = M.parseStatus(JSON.stringify(j))
  assert.strictEqual(s.storage.files, "12.0 GiB")
  assert.strictEqual(s.storage.afterDedup, "6.0 GiB")
  assert.strictEqual(s.storage.dedup, "2.0x")
  assert.strictEqual(s.storage.nodeDisk, "2.0 GiB")
  assert.strictEqual(s.storage.compression, "1.5x")
  assert.strictEqual(s.storage.share, "50.0%")      // 3 GiB of 6 GiB x 1 copy
  assert.strictEqual(s.storage.zstdChunks, 90)
})

test("an older build, with no efficiency at all, has no storage block", () => {
  const j = withFiles("fixture-status-1.0.8.json")
  delete j.efficiency
  assert.strictEqual(M.parseStatus(JSON.stringify(j)).storage, null)
})

test("node stats: an empty cluster", () => {
  const r = M.parseNodeStats(fs.readFileSync(path.join(__dirname, "fixture-stats-empty.json"), "utf8"), 1)
  const host = Object.keys(r)[0]
  assert.strictEqual(host, "3090")
  assert.strictEqual(r[host].answered, true)
  assert.strictEqual(r[host].disk, "0 B")
  assert.strictEqual(r[host].offered, "10.0 GiB")
  assert.strictEqual(r[host].compression, "")
  assert.strictEqual(r[host].share, "")
})

test("node stats: shares, compression and a member that did not answer", () => {
  const eff = (plain, disk) => ({ logical_bytes: 12 * GiB, referenced_bytes: 6 * GiB, inline_bytes: 0, local_plain_bytes: plain,
                                  local_disk_bytes: disk, raw_chunks: 0, zstd_chunks: 1 })
  const rows = [
    { member: 0, addr: "mini2.ts.net:7600", is_self: false, stats: { usage: { chunks: 5, stored_bytes: 2 * GiB, offer_bytes: 10 * GiB },
      efficiency: eff(4 * GiB, 2 * GiB), pending_gc_bytes: 1048576 } },
    { member: 1, addr: "vps1.ts.net:7600", is_self: false, stats: null }
  ]
  const r = M.parseNodeStats(JSON.stringify(rows), 3)
  assert.strictEqual(r.mini2.disk, "2.0 GiB")
  assert.strictEqual(r.mini2.compression, "2.0x")
  assert.strictEqual(r.mini2.share, "22.2%")        // 4 GiB of 6 GiB x 3 copies
  assert.strictEqual(r.mini2.garbage, "1.0 MiB")
  assert.strictEqual(r.vps1.answered, false)
})

test("node stats: nonsense is empty, not an error", () => {
  assert.deepStrictEqual(M.parseNodeStats("not json", 3), {})
  assert.deepStrictEqual(M.parseNodeStats('{"a":1}', 3), {})
})

// ---- StartFS 1.10: releases, sites, round trips, cluster upgrades --------------------------------------------------------
const live = () => JSON.parse(fs.readFileSync(path.join(__dirname, "fixture-status-1.10.2.json"), "utf8"))

test("1.10 members carry their site, release and round trip", () => {
  const s = M.parseStatus(JSON.stringify(live()))
  assert.strictEqual(s.ok, true)
  assert.strictEqual(M.health(s), "safe")
  const mini2 = s.members.find(m => m.host === "mini2")
  assert.strictEqual(mini2.site, "home")
  assert.strictEqual(mini2.release, "v1.10.2")
  assert.strictEqual(mini2.protocol, 15)
  assert.strictEqual(mini2.rtt, "5.2 ms")
  assert.strictEqual(s.members.find(m => m.self).rtt, "")
  assert.strictEqual(M.clusterRelease(s), "v1.10.2")
  // A finished upgrade stays in status with complete: true; it is not progress.
  assert.strictEqual(M.upgradeProgress(s), null)
})

test("unknown and upgrading members are not trouble; down ones are", () => {
  const j = live()
  j.members[0].state = "Unknown"
  j.members[2].state = "Upgrading"
  j.members[3].state = "Down"
  j.members[3].last_seen = { secs_ago: 720, exact: true }
  j.members[3].problem = "timed out"
  const s = M.parseStatus(JSON.stringify(j))
  assert.strictEqual(M.stateTone(s.members[0]), "quiet")
  assert.strictEqual(M.stateTone(s.members[2]), "quiet")
  assert.strictEqual(M.stateTone(s.members[3]), "bad")
  assert.strictEqual(M.memberLine(s.members[3]), "last seen 12 min ago  ·  timed out")
})

test("a rolling upgrade under way, and one held by a busy mount", () => {
  const j = live()
  j.upgrade = { release: "v1.10.3", lockstep: false, go: false, complete: false, split: [] }
  j.members.forEach(m => { m.upgrade = "Staged" })
  j.members[0].release = "v1.10.3"; j.members[0].upgrade = null
  j.members[2].upgrade = "Restarting"
  let p = M.upgradeProgress(M.parseStatus(JSON.stringify(j)))
  assert.strictEqual(p.target, "v1.10.3")
  assert.strictEqual(p.done, 1)
  assert.strictEqual(p.total, 7)
  assert.match(p.text, /one node at a time/)
  const s = M.parseStatus(JSON.stringify(j))
  assert.match(M.memberLine(s.members[2], undefined, "v1.10.3"), /^restarting on v1.10.3/)
  j.members[1].upgrade = "WaitingOnMount"
  p = M.upgradeProgress(M.parseStatus(JSON.stringify(j)))
  assert.strictEqual(p.waiting.length, 1)
  assert.match(p.text, /3090 waits for its mount/)
  j.members[4].upgrade = { Failed: "checksum mismatch" }
  p = M.upgradeProgress(M.parseStatus(JSON.stringify(j)))
  assert.match(p.text, /^Upgrade stopped: mini1 failed/)
})

test("releases compare as numbers", () => {
  assert.strictEqual(M.compareRelease("v1.10.2", "v1.9.9"), 1)
  assert.strictEqual(M.compareRelease("v1.10.2", "v1.10.2"), 0)
  assert.strictEqual(M.compareRelease("", "v1.0.0"), -1)
})

test("size boxes show what startfs config reads back", () => {
  assert.strictEqual(M.sizeInput(107374182400), "100G")
  assert.strictEqual(M.sizeInput(0), "0")
  assert.strictEqual(M.sizeInput(1536 * 1048576), "1536M")
  assert.ok(M.validSite("home") && M.validSite("") && !M.validSite("my site"))
})

test("activity: rates over the window, and pressure when the kernel has it", () => {
  const a = M.parseActivity(JSON.stringify({ enabled: true, window_secs: 60,
    peers: [{ member: 0, addr: "mini2.example.ts.net:7600", state: "Online", in_flight: 2,
              traffic: { sent: { chunk: { bytes: 61440, messages: 1 }, metadata: { bytes: 0, messages: 0 }, gossip: { bytes: 0, messages: 0 },
                                 other: { bytes: 0, messages: 0 } },
                         received: { chunk: { bytes: 0, messages: 0 }, metadata: { bytes: 0, messages: 0 }, gossip: { bytes: 6144, messages: 1 },
                                     other: { bytes: 0, messages: 0 } }, acknowledged: 1, timed_out: 0, retried: 0 } }],
    tick: { ticks: 10, avg_ms: 0.2, max_ms: 54, busy_fraction: 0.02 }, queue: { chunks: 0, oldest_secs: null },
    structures: { decoded_cache: { entries: 1, bytes: 1048576, limit_bytes: 134217728 } },
    resources: { rss_bytes: 95686656, cpu_secs: 29.7, threads: 9, cpu_pressure: { avg10: 0, avg60: 0.17 }, memory_pressure: null,
                 io_pressure: null, written_bytes: 0 } }))
  assert.strictEqual(a.out, "1.0 KiB/s")
  assert.strictEqual(a.in, "102 B/s".replace("102", String(6144 / 60)))
  assert.strictEqual(a.peers[0].host, "mini2")
  assert.strictEqual(a.queue, "empty")
  assert.strictEqual(a.memoryPressure, "not available")
  assert.strictEqual(a.readCache, "1.0 MiB of 128.0 MiB")
  assert.strictEqual(M.parseActivity("nope"), null)
})

test("a node that lags a release, with nothing to do, is not an upgrade under way", () => {
  const j = live()
  j.upgrade.complete = false
  j.members[4].release = "v1.10.1"
  assert.strictEqual(M.upgradeProgress(M.parseStatus(JSON.stringify(j))), null)
})

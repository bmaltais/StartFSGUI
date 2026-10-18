const test = require("node:test")
const assert = require("node:assert")
const fs = require("node:fs")
const path = require("node:path")

// StartFSModel.js is a QML library; load it as a plain script.
const source = fs.readFileSync(path.join(__dirname, "..", "StartFSModel.js"), "utf8").replace(/^\.pragma.*$/m, "")
const M = new Function(source + "\nreturn { bytes, formatBytes, parseStatus, parseNodeStats, health, headline, validSize }")()

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
  for (const ok of ["0", "500M", "10G", "2T", "1.5GiB"]) assert.ok(M.validSize(ok), ok)
  for (const bad of ["", "G", "10 G", "-1", "10X"]) assert.ok(!M.validSize(bad), bad)
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
  j.repair = { at_risk: 1, degraded: 2 }
  assert.strictEqual(M.headline(M.parseStatus(JSON.stringify(j))), "Safe, repairing 3 chunks")
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

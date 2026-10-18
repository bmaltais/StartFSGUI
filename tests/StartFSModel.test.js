const test = require("node:test")
const assert = require("node:assert")
const fs = require("node:fs")
const path = require("node:path")

// StartFSModel.js is a QML library; load it as a plain script.
const source = fs.readFileSync(path.join(__dirname, "..", "StartFSModel.js"), "utf8").replace(/^\.pragma.*$/m, "")
const M = new Function(source + "\nreturn { bytes, formatBytes, parseStatus, health, headline, validSize }")()

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

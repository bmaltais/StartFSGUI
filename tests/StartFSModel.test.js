const test = require("node:test")
const assert = require("node:assert")
const fs = require("node:fs")
const path = require("node:path")

// StartFSModel.js is a QML library; load it as a plain script.
const source = fs.readFileSync(path.join(__dirname, "..", "StartFSModel.js"), "utf8").replace(/^\.pragma.*$/m, "")
const M = new Function(source + "\nreturn { bytes, parseStatus, health, headline, validSize }")()

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

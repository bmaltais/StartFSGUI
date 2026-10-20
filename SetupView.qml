// The StartFS window: the whole filesystem in detail (is it safe, where the space went), upgrading every node, the settings that
// are the filesystem's (copies, purging deleted data), then the plugin's own (launcher entry, command line, bar icon, window
// memory). Shown once after the plugin is enabled, and again from the manager's gear button or its health banner. Every change
// applies the moment it is made; a change that cannot be made flips back and says why. The look is SettingsWindow's.
import QtQuick
import qs.Commons
import qs.Ui
import "StartFSModel.js" as Model

SettingsWindow {
  id: view

  property var svc
  // key -> value, what the controls show. Filled from the system by refreshVals().
  property var vals: ({})

  readonly property var integ: view.svc.integ
  readonly property var st: view.svc.status
  readonly property var progress: view.svc.progress
  readonly property string release: Model.clusterRelease(view.st)
  readonly property bool cliBlocked: !!(view.integ.cli && view.integ.cli.state === "other")
  // The daemon answers `status`; without it there is nothing to set on the filesystem.
  readonly property bool noDaemon: !view.st.ok

  title: "StartFS"
  titleIcon: Qt.resolvedUrl("assets/startfsgui.svg").toString().replace("file://", "")
  subtitle: view.st.ok ? view.st.fs.toUpperCase() + (view.release !== "" ? "  ·  " + view.release : "") : "SETTINGS"
  values: view.vals
  searchPlaceholder: "Find a detail or setting"
  footerText: view.integ.done ? "Changes apply instantly" : "Choose what to switch on. Changes apply instantly."
  initialPage: Math.max(0, view.pages.map(function (p) { return p.title }).indexOf(view.svc.setupPage))

  function info(label, text, tone, hint) { return { key: "", type: "info", label: label, text: text, tone: tone || "", hint: hint || "" } }
  function long(label, text, tone) { return { key: "", type: "info", stacked: true, label: label, text: text, tone: tone || "" } }
  function note(key) {
    var s = view.svc
    if (s.lastKey !== key || s.busy || s.notice === "") return null
    return { kind: s.noticeIsError ? "bad" : "ok", text: s.notice }
  }

  // ---- the filesystem, read ------------------------------------------------------------------
  readonly property var overviewFields: {
    var s = view.st
    if (!s.ok) return [view.long("The daemon", s.stopping ? "It is restarting." : "It does not answer. Start it with: systemctl --user start startfs", "bad")]
    var bad = view.svc.health !== "safe"
    var up = s.members.filter(function (m) { return m.state === "up" }).length
    var f = [
      view.info("Data", Model.headline(s), bad ? "bad" : "ok",
        s.data === "SAFE" ? "Every file has all its copies." : "In StartFS's words: " + s.data.toLowerCase() + "."),
      view.info("Copies", s.possible + " of " + s.wanted + " possible", s.possible < s.wanted ? "bad" : ""),
      view.info("Nodes", up + " of " + s.nodes + " up", up < s.nodes ? "bad" : ""),
      view.info("Usable space", s.usable, "", "What every node offers, divided by the copies kept.")
    ]
    if (s.repair) f.push(view.info("Repair", s.repair.atRisk + " chunks at risk, " + s.repair.degraded + " degraded", "bad"))
    if (s.unreplicated > 0) f.push(view.info("Missing copies", s.unreplicated + " chunks", "bad"))
    if (s.rechecking > 0) f.push(view.info("Re-checking", s.rechecking + " chunks", "muted", "After a restart this node asks the others what they hold."))
    s.stranded.forEach(function (x) {
      var mb = s.members.filter(function (m) { return String(m.id) === String(x.member) })[0]
      f.push(view.info("Only on " + (mb ? mb.host : "member " + x.member), x.chunks + " chunks", "bad", "It is down; bring it back before removing it."))
    })
    if (s.unheard.length > 0) f.push(view.info("Partial view", s.unheard.length + " nodes have not reported yet", "muted"))
    if (s.warnings.length > 0) f.push(view.long("Warnings", s.warnings.join("\n"), "bad"))
    if (s.conflicts.length > 0) f.push(view.long("Conflict copies", s.conflicts.join("\n"), "bad"))
    if (s.scrubInfo) f.push(view.info("Scrub", s.scrub, "", "Reads every copy now and then to catch a damaged one."))
    return f
  }

  readonly property var storageFields: {
    var s = view.st
    var o = s.storage
    if (!s.ok) return [view.info("Storage", "not known", "muted")]
    if (!o) return [view.info("In files", "nothing yet", "muted"), view.info("Usable space", s.usable)]
    return [
      view.info("In files", o.files, "", "The size of every file, as you see them."),
      view.info("After deduplication", o.afterDedup + (o.dedup !== "" ? "  (" + o.dedup + ")" : ""), "", "The same data is kept once."),
      view.info("Kept across the nodes", o.expected, "", "Everything after deduplication, " + s.copies + " times."),
      view.info("Usable space", s.usable),
      view.info("This node, on disk", o.nodeDisk),
      view.info("This node's compression", o.compression !== "" ? o.compression : "none"),
      view.info("This node's share", o.share, "", "Its part of all the copies.")
    ]
  }

  // ---- upgrading every node ---------------------------------------------------------------------
  property string tag: ""
  property bool confirmUpgrade: false
  property bool confirmPurge: false
  Timer { id: confirmTimer; interval: 3000; onTriggered: { view.confirmUpgrade = false; view.confirmPurge = false } }
  readonly property bool tagOk: view.tag === "" || /^v[0-9]+\.[0-9]+\.[0-9]+$/.test(view.tag)
  readonly property string goal: view.tag !== "" ? view.tag : view.svc.latest
  readonly property var behindMembers: view.st.members.filter(function (m) {
    return m.release !== "" && view.release !== "" && m.release !== view.release })

  readonly property var upgradeFields: [
    view.info("The nodes run", view.release !== "" ? view.release : "not reported",
      view.behindMembers.length ? "bad" : "",
      view.behindMembers.length ? view.behindMembers.map(function (m) { return m.host + " runs " + m.release }).join(", ") + "." : ""),
    { key: "latest", type: "action", label: "Newest release",
      buttonText: view.svc.latestBusy ? "Asking..." : "Check again",
      note: { kind: view.svc.latestError !== "" ? "bad" : "muted",
              text: view.svc.latestError !== "" ? view.svc.latestError : view.svc.latest !== "" ? view.svc.latest + " on GitHub" : "Not asked yet" },
      hint: "StartFS's newest stable release." },
    { key: "tag", type: "text", label: "Release", placeholder: view.svc.latest !== "" ? view.svc.latest + " (the newest)" : "the newest",
      note: view.tagOk ? null : { kind: "bad", text: "A release looks like v1.10.3." },
      hint: "Leave empty for the newest, or name one like v1.10.3." },
    { key: "upgrade", type: "action", label: view.progress ? "Upgrading" : "Upgrade every node",
      disabled: view.noDaemon || !view.tagOk || view.svc.busy || (view.progress !== null && view.progress.failed.length === 0),
      buttonText: view.confirmUpgrade ? "Click again to upgrade" : "Upgrade to " + (view.goal !== "" ? view.goal : "the newest"),
      note: view.progress ? { kind: view.progress.failed.length ? "bad" : "ok",
                              text: view.progress.text + ": " + view.progress.done + " of " + view.progress.total + " done." }
        : view.note("upgrade"),
      hint: "Each node downloads it, then restarts on it, one at a time; all together when the protocol changes. "
        + "A node's mount drops for a few seconds while it restarts." }
  ]

  readonly property var filesystemFields: [
    view.info("Name", view.st.fs !== "" ? view.st.fs : "none"),
    { key: "copies", type: "choice", label: "Copies", disabled: view.noDaemon, note: view.note("copies"),
      options: [ { value: 1, label: "1" }, { value: 2, label: "2" }, { value: 3, label: "3" }, { value: 4, label: "4" }, { value: 5, label: "5" } ],
      hint: "Copies of every file, on different machines. Lowering waits until every file has all its copies." },
    { key: "purge", type: "action", label: "Free deleted data now", danger: view.confirmPurge, disabled: view.noDaemon,
      buttonText: view.confirmPurge ? "Click again to free it" : "Free now",
      note: view.note("purge"),
      hint: "Every node frees deleted files' data now instead of keeping it "
        + (view.st.filesystem ? Model.durationText(view.st.filesystem.gc_retention_secs) : "7 days") + ". Needs every node up." },
    view.info("Repair waits", view.st.filesystem ? Model.durationText(view.st.filesystem.repair_grace_secs) : "", "",
      "Before copying a missing node's data elsewhere. Set when the filesystem was made."),
    view.info("Sleeping nodes covered", view.st.filesystem && view.st.filesystem.standin_days !== undefined
      ? view.st.filesystem.standin_days + " days" : "", "", "How long the others keep stand-in copies for a node that sleeps.")
  ]

  pages: [
    { title: "Overview", fields: view.overviewFields },
    { title: "Storage", fields: view.storageFields },
    { title: "Upgrade", fields: view.upgradeFields },
    { title: "Filesystem", fields: view.filesystemFields },
    { title: "General", fields: [
      { key: "launcher", type: "bool", label: "App launcher entry",
        hint: "Adds StartFS to the app launcher (SUPER + space) to open the manager." },
      { key: "cli", type: "bool", label: "Command line", disabled: view.cliBlocked,
        hint: view.cliBlocked
          ? view.integ.cli.path + " already exists and is not StartFSGUI, so it is left alone."
          : "Links " + (view.integ.cli ? view.integ.cli.path : "") + " so you can run startfsgui in a terminal." }
    ] },
    { title: "Bar", fields: [
      { key: "barIcon", type: "bool", label: "Bar icon",
        hint: "An icon on the Omarchy bar that opens the manager and turns red when your data is not safe. You can drag it around the bar." }
    ] },
    { title: "Window", fields: [
      { key: "rsize", type: "bool", label: "Remember size",
        hint: "The manager reopens at the size you gave it. Drag its bottom-right corner to resize." },
      { key: "rpos", type: "bool", label: "Remember position",
        hint: "The manager reopens where you left it. Drag its top strip to move it. Switched off, it opens centred." }
    ] }
  ]

  // The command-line options that make each plugin setting happen.
  readonly property var flags: ({
    launcher: "--launcher", cli: "--cli", barIcon: "--bar-icon", rsize: "--remember-size", rpos: "--remember-position"
  })

  onChanged: function (key, value) {
    var next = Object.assign({}, view.vals)
    if (key === "copies") {
      next.copies = value
      view.vals = next
      view.svc.applyCluster("copies", value)
    } else if (key === "tag") {
      view.tag = String(value).trim()
      next.tag = view.tag
      view.vals = next
    } else if (key === "latest") {
      view.svc.checkLatest(true)
    } else if (key === "upgrade") {
      if (!view.confirmUpgrade) { view.confirmUpgrade = true; confirmTimer.restart(); return }
      view.confirmUpgrade = false
      view.svc.startUpgrade(view.tag)
    } else if (key === "purge") {
      if (!view.confirmPurge) { view.confirmPurge = true; confirmTimer.restart(); return }
      view.confirmPurge = false
      view.svc.purge()
    } else if (view.flags[key] !== undefined) {
      next[key] = value
      view.vals = next
      view.svc.applySetting([view.flags[key], String(value)])
    }
  }
  onEdited: function (key, text) { if (key === "tag") view.tag = text.trim() }

  // What is set right now, read back from the system.
  function refreshVals() {
    var i = view.integ
    if (i.cli) view.vals = Object.assign({}, view.vals, { launcher: i.launcher, cli: i.cli.state === "ours",
      barIcon: i.barIcon, rsize: i.rememberSize, rpos: i.rememberPosition })
    view.refreshNode()
  }
  function refreshNode() { view.vals = Object.assign({}, view.vals, { copies: view.st.copies, tag: view.tag }) }
  function opened() { view.reset(); view.confirmingReset = false; view.tag = ""; view.refreshVals() }
  onVisibleChanged: if (visible) view.opened()
  Component.onCompleted: view.opened()
  Connections {
    target: view.svc
    // Not while changes are still being made: the read-back would undo a click.
    function onIntegChanged() { if (view.visible && !view.svc.setupBusy) view.refreshVals() }
    // The daemon's answer is the truth, so a refused change flips its control back.
    function onStatusChanged() { if (view.visible && !view.svc.busy) view.refreshNode() }
  }

  // The recommended set, in one go: what a first run offers, and what Reset goes back to.
  property bool confirmingReset: false
  Timer { id: resetTimer; interval: 3000; onTriggered: view.confirmingReset = false }
  function applyDefaults() {
    var d = view.integ.defaults  // the CLI's recommended set
    if (!d) return
    var v = { launcher: d.launcher, cli: d.cli && !view.cliBlocked, barIcon: d.barIcon, rsize: d.rememberSize, rpos: d.rememberPosition }
    view.vals = Object.assign({}, view.vals, v)
    var args = []
    for (var k in v) args.push(view.flags[k], String(v[k]))
    view.svc.applySetting(args)
  }

  // ---- footer ----------------------------------------------------------------------------
  // A first run offers the recommended set in one click, or to leave it for later.
  SettingsPill {
    visible: !view.integ.done
    text: "Not now"
    onClicked: view.svc.skipSetup()
  }
  SettingsPill {
    visible: !view.integ.done
    text: "Enable recommended"
    primary: true
    onClicked: view.applyDefaults()
  }
  // Afterwards, the one quiet way back. It resets the plugin's own settings, never the filesystem's.
  SettingsPill {
    visible: !!view.integ.done
    text: view.confirmingReset ? "Click again to reset everything" : "Reset to defaults"
    danger: view.confirmingReset
    onClicked: {
      if (view.confirmingReset) { view.confirmingReset = false; resetTimer.stop(); view.applyDefaults() }
      else { view.confirmingReset = true; resetTimer.restart() }
    }
  }
}

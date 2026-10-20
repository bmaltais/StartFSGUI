// One node's window, the way StartAppImage opens one app's settings: its status in detail, where its space goes, what it is
// doing (this node only), its settings and its maintenance. The look is SettingsWindow's. Settings apply the moment they are
// made: on this node with `startfs config`, on another over ssh (`startfsgui set --host`).
import QtQuick
import qs.Commons
import qs.Ui
import "StartFSModel.js" as Model

SettingsWindow {
  id: view

  property var svc
  // The member as the latest status has it (the window stays on it across reads, by its number).
  readonly property var m: view.svc.nodeMember
  readonly property bool self: !!view.m.self
  readonly property bool up: view.m.state === "up"
  readonly property var n: view.svc.nodeStats[view.m.host]
  readonly property var st: view.svc.status
  readonly property var act: view.svc.activity
  readonly property string target: view.svc.progress ? view.svc.progress.target : ""
  readonly property bool installing: view.svc.installHost === view.m.host

  title: view.m.host || ""
  titleGlyph: view.self ? "" : ""
  subtitle: (view.self ? "THIS NODE" : "NODE") + (view.m.release ? "  ·  " + view.m.release : "")
  footerText: view.self ? "Changes apply instantly" : "Changes apply over ssh"
  searchPlaceholder: "Find a detail or setting"
  initialPage: Math.max(0, view.pages.map(function (p) { return p.title }).indexOf(view.svc.nodePage))

  property var vals: ({})
  values: view.vals
  function refreshVals() {
    view.vals = { offer: Model.sizeInput(view.m.offerBytes), weight: Model.sizeInput(view.m.weightBytes), site: view.m.site,
                  activity: view.act ? view.act.enabled : true }
  }
  function opened() { view.reset(); view.refreshVals(); view.confirmLeave = false; view.confirmRemove = false }
  onVisibleChanged: if (visible) view.opened()
  // Built while the frame is already showing, so it may never see visible change.
  Component.onCompleted: view.opened()
  Connections {
    target: view.svc
    // The daemon's answer is the truth, so a refused change goes back; not while one is still being made.
    function onStatusChanged() { if (view.visible && !view.svc.busy) view.refreshVals() }
    function onActivityChanged() { if (view.visible && !view.svc.busy) view.refreshVals() }
  }

  // Two clicks for what cannot be undone; the first one lapses after 3 seconds.
  property bool confirmLeave: false
  property bool confirmRemove: false
  Timer { id: confirmTimer; interval: 3000; onTriggered: { view.confirmLeave = false; view.confirmRemove = false } }

  // ---- words ------------------------------------------------------------------------------------
  function info(label, text, tone, hint) { return { key: "", type: "info", label: label, text: text, tone: tone || "", hint: hint || "" } }
  function long(label, text, tone) { return { key: "", type: "info", stacked: true, label: label, text: text, tone: tone || "" } }
  function when(ns) { return ns ? Qt.formatDateTime(new Date(ns / 1000000), "d MMM yyyy, hh:mm") : "never" }
  function stat(f, missing) {
    if (view.n === undefined) return view.svc.statsBusy ? "Asking..." : "Not read yet"
    if (!view.n.answered) return "No answer"
    return f(view.n) || missing || "none"
  }

  readonly property var statusFields: {
    var m = view.m
    var f = [view.info("State", Model.stateText(m), Model.stateTone(m) === "bad" ? "bad" : "")]
    if (m.upgradeStep !== "") f.push(view.info("Upgrade", Model.stepText(m, view.target), m.upgradeStep === "failed" ? "bad" : "ok"))
    if (m.problem !== "") f.push(view.long("Why it cannot be reached", m.problem, "bad"))
    if (m.lastSeen) f.push(view.info("Last seen", (m.lastSeen.exact ? "" : "over ") + Model.durationText(m.lastSeen.secs) + " ago"))
    if (m.standinSecs !== null) f.push(view.info("Stand-in copies", "kept " + Model.durationText(m.standinSecs) + " more", "",
      "While it sleeps, the others hold extra copies of what it has."))
    if (m.behind) f.push(view.info("Behind", Model.durationText(m.behind.tickSecs) + ", " + m.behind.messages + " messages queued", "bad",
      "It is sent nothing new until it catches up."))
    f.push(view.info("Address", m.address))
    f.push(view.info("Member number", m.id))
    f.push(view.info("Site", m.site !== "" ? m.site : "none", m.site !== "" ? "" : "muted",
      "Copies are spread across sites, so losing one site loses no data."))
    f.push(view.info("Release", m.release !== "" ? m.release + (m.protocol !== null ? "  (protocol " + m.protocol + ")" : "")
      : "not reported (older than 1.10)", m.release === "" ? "muted" : ""))
    if (!view.self) f.push(view.info("Round trip", m.rtt !== "" ? m.rtt : "not measured", m.rtt !== "" ? "" : "muted",
      "Measured from this node."))
    return f
  }

  readonly property var storageFields: {
    var m = view.m
    var s = view.st
    var f = [
      view.info("Offered", m.offered),
      view.info("Weight", m.weightBytes > 0 ? Model.formatBytes(m.weightBytes) : "follows the offer"),
      view.info("On disk", view.stat(function (x) {
        return x.disk + (x.offerBytes > 0 ? "  (" + Math.round(100 * x.diskBytes / x.offerBytes) + "% of the offer)" : "") })),
      view.info("Chunks", view.stat(function (x) { return String(x.chunks) })),
      view.info("Compression", view.stat(function (x) { return x.compression }, "nothing to compress")),
      view.info("Share of the copies", view.stat(function (x) { return x.share }, "none"), "",
        "Its part of all the copies the filesystem keeps."),
      view.info("Waiting to be freed", view.stat(function (x) { return x.garbage }, "nothing"))
    ]
    if (view.self && s.ok) {
      f.push(view.info("Waiting for replication", s.staging !== "" ? s.staging : "nothing"))
      f.push(view.info("Cache", s.cache, "", "Chunks fetched from the others, kept for the next read."))
      if (s.scrubInfo) f.push(view.info("Scrub", s.scrub + (s.scrubInfo.remaining > 0 ? ", " + s.scrubInfo.remaining + " replicas to check" : ""),
        "", "Last pass " + view.when(s.scrubInfo.last_pass) + ", next " + view.when(s.scrubInfo.next_pass) + "."))
      if (s.gc) f.push(view.info("Garbage collection", Model.formatBytes(s.gc.pending_bytes) + " pending"
        + (s.gc.purging ? ", purging" : "") + ", " + Model.formatBytes(s.gc.reclaimed_bytes) + " reclaimed"))
      if (s.log) f.push(view.info("Metadata", s.log.objects + " objects, " + s.log.entries + " log entries"))
    }
    return f
  }

  readonly property var activityFields: {
    var a = view.act
    if (!a) return [view.info("Activity", view.svc.activityBusy ? "Reading..." : "Not available", "muted")]
    var f = [
      view.info("Sending", a.out, "", "Over the last " + a.window + " s, to every other node."),
      view.info("Receiving", a.in),
      view.info("In flight", a.inFlight + " messages" + (a.timedOut + a.retried > 0 ? ", " + a.timedOut + " timed out, " + a.retried + " retried" : "")),
      view.info("Replication queue", a.queue),
      view.info("Work loop", a.tick !== "" ? a.tick : "not measured yet", a.tick !== "" ? "" : "muted"),
      view.info("Memory", a.memory + ", " + a.threads + " threads"),
      view.info("CPU", a.cpu),
      view.info("Written to disk", a.written, "", "Since the daemon started."),
      view.info("Read cache", a.readCache !== "" ? a.readCache : "off"),
      view.info("CPU pressure", a.cpuPressure, "muted"),
      view.info("Memory pressure", a.memoryPressure, "muted"),
      view.info("Disk pressure", a.ioPressure, "muted")
    ]
    if (!a.enabled) f.unshift(view.info("Counters", "off: traffic is not counted", "muted", "Switch them on under Maintenance."))
    a.peers.forEach(function (p) {
      f.push(view.info(p.host, p.hasTraffic ? "out " + p.out + ",  in " + p.in : Model.stateText({ state: p.state }), p.hasTraffic ? "" : "muted"))
    })
    return f
  }

  // What the last change to one of this node's settings did, under its control.
  function noteFor(key) {
    var s = view.svc
    if (s.lastKey !== view.m.host + ":" + key || s.busy || s.notice === "") return null
    return { kind: s.noticeIsError ? "bad" : "ok", text: s.notice }
  }
  readonly property string remoteHint: view.self ? "" : " Changed on " + view.m.host + " over ssh."
  readonly property bool settable: view.self || view.up

  readonly property var settingsFields: [
    { key: "offer", type: "text", label: "Space offered", placeholder: "100G", disabled: !view.settable, note: view.noteFor("offer"),
      hint: "Disk this node gives to StartFS, like 500G or 2T. 0 makes it a pure client." + view.remoteHint },
    { key: "weight", type: "text", label: "Weight", placeholder: "0", disabled: !view.settable, note: view.noteFor("weight"),
      hint: "How much of the new copies it takes, as a size. 0 follows the space offered. Changing it moves data." + view.remoteHint },
    { key: "site", type: "text", label: "Site", placeholder: "home", disabled: !view.settable, note: view.noteFor("site"),
      hint: "Where the machine is, like home or cloud. Copies spread across sites. Empty makes it a site of its own." + view.remoteHint }
  ]

  readonly property var maintenanceFields: view.self ? [
    { key: "force", type: "action", label: "Restart on the new release", buttonText: "Restart now",
      disabled: view.m.upgradeStep !== "waiting on mount",
      hint: view.m.upgradeStep === "waiting on mount"
        ? "Files on the mount are open, so the upgrade waits. Restarting now drops the mount for a few seconds."
        : "Used when an upgrade waits because files on the mount are open. Nothing waits now." },
    { key: "activity", type: "bool", label: "Activity counters",
      hint: "Counts this node's traffic for the Activity page. Back on when the daemon restarts." },
    { key: "logs", type: "action", label: "Daemon log", buttonText: "Open in a terminal",
      hint: "journalctl --user -u startfs, followed." },
    { key: "leave", type: "action", label: "Leave the filesystem", danger: view.confirmLeave,
      buttonText: view.confirmLeave ? "Click again to leave" : "Leave",
      note: view.svc.lastKey === view.m.host + ":leave" && view.svc.notice !== "" ? { kind: view.svc.noticeIsError ? "bad" : "ok", text: view.svc.notice } : null,
      hint: "This node hands its data to the others, then leaves. Its files stay on the others. It cannot be undone." }
  ] : [
    { key: "install", type: "action", label: "Reinstall StartFS",
      buttonText: view.installing ? "Installing..." : "Run the installer",
      disabled: view.svc.installing,
      note: view.installing || view.svc.installHostLast === view.m.host ? { kind: view.svc.installFailed ? "bad" : "muted",
        text: view.svc.installLines.join("\n") } : null,
      hint: "For a node older than 1.10 or one that does not start. Runs StartFS's installer on " + view.m.host + " over ssh"
        + (Model.clusterRelease(view.st) !== "" ? ", pinned to " + Model.clusterRelease(view.st) : "") + "." },
    { key: "remove", type: "action", label: "Remove from the filesystem", danger: view.confirmRemove,
      buttonText: view.confirmRemove ? "Click again to remove" : "Remove",
      disabled: !(view.m.state === "down" || view.m.state === "lost"),
      note: view.svc.lastKey === view.m.host + ":remove" && view.svc.notice !== "" ? { kind: view.svc.noticeIsError ? "bad" : "ok", text: view.svc.notice } : null,
      hint: view.m.state === "down" || view.m.state === "lost"
        ? "For a machine that is gone for good. Its copies are made again on the others."
        : "Only a node that is down can be removed. One that is up leaves from its own StartFS." }
  ]

  pages: {
    var p = [{ title: "Status", fields: view.statusFields }, { title: "Storage", fields: view.storageFields }]
    if (view.self) p.push({ title: "Activity", fields: view.activityFields })
    p.push({ title: "Settings", fields: view.settingsFields }, { title: "Maintenance", fields: view.maintenanceFields })
    return p
  }

  // The Activity page reads this node's counters while it is shown.
  readonly property bool onActivity: view.visible && view.self && !view.searching
    && view.pages[view.page] !== undefined && view.pages[view.page].title === "Activity"
  onOnActivityChanged: view.svc.watchActivity(view.onActivity)

  onChanged: function (key, value) {
    if (key === "offer" || key === "weight" || key === "site") {
      const v = String(value).trim()
      const ok = key === "site" ? Model.validSite(v) : Model.validSize(v)
      if (!ok) {
        view.svc.say(view.m.host + ":" + key, true, key === "site" ? "Letters, digits, dots, dashes and underscores only."
          : "Not a size. Use a whole number with K, M, G or T, like 500G.")
        return
      }
      view.vals = Object.assign({}, view.vals, { [key]: v })
      view.svc.apply(view.m, key, v)
    } else if (key === "activity") {
      view.vals = Object.assign({}, view.vals, { activity: value })
      view.svc.apply(view.m, "activity", value ? "on" : "off")
    } else if (key === "force") {
      view.svc.forceUpgrade()
    } else if (key === "logs") {
      view.svc.openLogs()
    } else if (key === "install") {
      view.svc.install(view.m, Model.clusterRelease(view.st))
    } else if (key === "leave") {
      if (!view.confirmLeave) { view.confirmLeave = true; confirmTimer.restart(); return }
      view.confirmLeave = false
      view.svc.leave()
    } else if (key === "remove") {
      if (!view.confirmRemove) { view.confirmRemove = true; confirmTimer.restart(); return }
      view.confirmRemove = false
      view.svc.removeMember(view.m)
    }
  }
}

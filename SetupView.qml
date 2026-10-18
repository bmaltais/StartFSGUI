// The settings window: this node's two settings (space offered, copies), then launcher entry, command line, bar icon and the
// manager's window memory. Shown once after the plugin is enabled, and again from the manager's gear button. Every change
// applies the moment it is made, as in StartBar; a change that cannot be made flips back and says why. The look is
// SettingsWindow's.
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
  readonly property bool cliBlocked: !!(view.integ.cli && view.integ.cli.state === "other")
  // The daemon answers `status`; without it there is nothing to set on the node.
  readonly property bool noDaemon: !view.st.ok
  // Settings that go to the daemon (`startfsgui set`), as opposed to the plugin's own (`startfsgui setup`).
  readonly property var nodeKeys: ["offer", "copies"]

  title: "StartFS"
  subtitle: "SETTINGS"
  values: view.vals
  footerText: view.integ.done ? "Changes apply instantly" : "Choose what to switch on. Changes apply instantly."

  // ---- what there is to set -----------------------------------------------------
  pages: [
    { title: "Node", fields: [
      { key: "offer", type: "text", stacked: true, label: "Space offered", disabled: view.noDaemon, placeholder: "500G",
        note: view.noteFor("offer"),
        hint: view.noDaemon ? "The StartFS daemon is not running, so there is nothing to set."
          : "Disk this node gives to StartFS, like 500G or 2T. 0 makes it a pure client." },
      { key: "copies", type: "choice", label: "Copies", disabled: view.noDaemon, note: view.noteFor("copies"),
        options: [ { value: 1, label: "1" }, { value: 2, label: "2" }, { value: 3, label: "3" }, { value: 4, label: "4" }, { value: 5, label: "5" } ],
        hint: "Copies of every file, on different machines, for the whole filesystem. Lowering waits until every file has all its copies." }
    ] },
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

  // What the last change to a node setting did, shown under its control: why it failed, or that it was saved.
  function noteFor(key) {
    var s = view.svc
    if (s.lastKey !== key || s.busy || s.notice === "") return null
    return { kind: s.noticeIsError ? "bad" : "ok", text: s.notice }
  }

  // The command-line options that make each plugin setting happen.
  readonly property var flags: ({
    launcher: "--launcher", cli: "--cli", barIcon: "--bar-icon", rsize: "--remember-size", rpos: "--remember-position"
  })

  onChanged: function (key, value) {
    var next = Object.assign({}, view.vals)
    next[key] = value
    if (view.nodeKeys.indexOf(key) !== -1) {
      // Checked here as well as in the CLI, so a typo is said at once instead of after a round trip.
      if (key === "offer" && !Model.validSize(value)) {
        view.svc.notice = "Not a size. Use a number with K, M, G or T, like 500G."
        view.svc.noticeIsError = true
        view.svc.lastKey = "offer"
        return
      }
      view.vals = next
      view.svc.apply(key, typeof value === "string" ? value.trim() : value)
      return
    }
    view.vals = next
    view.svc.applySetting([view.flags[key], String(value)])
  }

  // What is set right now, read back from the system.
  function refreshVals() {
    var i = view.integ
    if (!i.cli) return
    view.vals = Object.assign({}, view.vals, { launcher: i.launcher, cli: i.cli.state === "ours",
      barIcon: i.barIcon, rsize: i.rememberSize, rpos: i.rememberPosition })
    view.refreshNode()
  }
  function refreshNode() {
    view.vals = Object.assign({}, view.vals, { offer: view.st.offered.replace(/\s+/g, ""), copies: view.st.copies })
  }
  onVisibleChanged: if (visible) { view.reset(); view.confirmingReset = false; view.refreshVals() }
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
  // Afterwards, the one quiet way back. It resets the plugin's own settings, never the cluster's.
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

// StartFSGUI: see whether StartFS data is safe, and configure this node, from the Omarchy shell.
// This file owns the state, every call to bin/startfsgui, the IPC entry points and the window. ManagerView.qml draws what is in it.
//
//   omarchy-shell io.github.bmaltais.startfsgui open       toggle the manager
//   omarchy-shell io.github.bmaltais.startfsgui refresh    read the status again
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "StartFSModel.js" as Model

Item {
  id: root

  // Injected by omarchy-shell (the plugin service loader).
  property var shell: null

  readonly property string cli: Qt.resolvedUrl("bin/startfsgui").toString().replace("file://", "")
  readonly property int shadow: Style.space(14)
  readonly property int radius: Math.max(Style.cornerRadius, Style.space(10))

  property bool shown: false
  property var targetScreen: null

  // ---- the filesystem ------------------------------------------------------------------
  property var status: Model.parseStatus("")
  readonly property string health: Model.health(root.status)
  property bool loaded: false               // the first read has finished, so the window never opens empty
  property bool busy: false                 // a setting is being applied
  property string notice: ""
  property bool noticeIsError: false

  function refresh() { if (!statusProc.running) statusProc.running = true }

  // The window reads fast while it is open; the bar icon needs only a slow look.
  Timer { interval: root.shown ? 5000 : 30000; running: true; repeat: true; onTriggered: root.refresh() }
  Component.onCompleted: root.refresh()

  Process {
    id: statusProc
    command: [root.cli, "status"]
    stdout: StdioCollector {
      onStreamFinished: { root.status = Model.parseStatus(text); root.loaded = true }
    }
    // A daemon that is not running prints nothing useful: the status stays "unknown", which the window says plainly.
    onExited: (code, status) => { if (code !== 0) { root.status = Model.parseStatus(""); root.loaded = true } }
  }

  // ---- applying a setting -----------------------------------------------------------------
  // Everything goes through `startfsgui set`, which checks the value before the daemon sees it and answers {ok} or {ok:false,error}.
  function apply(key, value) {
    if (root.busy) return
    setProc.pendingKey = key
    setProc.command = [root.cli, "set", key, String(value)]
    setProc.reply = ""
    root.busy = true
    setProc.running = true
  }
  Process {
    id: setProc
    property string pendingKey: ""
    property string reply: ""
    stdout: SplitParser { onRead: line => setProc.reply = line }
    stderr: SplitParser { onRead: line => { if (setProc.reply === "") setProc.reply = JSON.stringify({ ok: false, error: line }) } }
    onExited: (code, exitStatus) => {
      var r = ({ ok: false, error: "exit code " + code })
      try { r = JSON.parse(setProc.reply) } catch (e) {}
      root.busy = false
      root.noticeIsError = !r.ok
      root.notice = r.ok ? "Saved." : r.error
      root.refresh()
    }
  }
  Timer { id: noticeTimer; interval: 6000; onTriggered: root.notice = "" }
  onNoticeChanged: if (root.notice !== "") noticeTimer.restart()

  // ---- the bar icon's status ---------------------------------------------------------------
  readonly property string statusDir: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/startfsgui"
  property bool statusDirReady: false
  Process { running: true; command: ["mkdir", "-p", root.statusDir]; onExited: root.statusDirReady = true }
  FileView { id: statusFile; path: root.statusDir + "/status"; printErrors: false; atomicWrites: true }
  function writeStatus() { if (root.statusDirReady && root.loaded) statusFile.setText(root.health) }
  onHealthChanged: root.writeStatus()
  onLoadedChanged: root.writeStatus()
  onStatusDirReadyChanged: root.writeStatus()

  // ---- showing and hiding -------------------------------------------------------------------
  function show() { root.refresh(); root.shown = true }
  function close() { root.shown = false }
  IpcHandler {
    target: "io.github.bmaltais.startfsgui"
    function state(): string { return JSON.stringify(root.status) }
    function refresh(): string { root.refresh(); return "ok" }
    function open(): void { if (root.shown) root.close(); else root.show() }
    function toggle(): void { if (root.shown) root.close(); else root.show() }
    function close(): void { root.close() }
  }

  // ---- the window ------------------------------------------------------------------------
  PanelWindow {
    id: win
    visible: root.shown && (root.loaded || slow)
    property bool slow: false
    screen: root.targetScreen
    color: "transparent"
    anchors.left: true
    anchors.right: true
    anchors.top: true
    anchors.bottom: true
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-startfsgui"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // If the first read is slow the window appears anyway, saying it is waiting.
    Timer { interval: 700; running: root.shown; onTriggered: win.slow = true }
    onVisibleChanged: if (!visible) win.slow = false

    // Click outside the card to dismiss it.
    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
      MouseArea { anchors.fill: parent; onClicked: root.close() }
    }

    RectangularShadow {
      anchors.fill: frame
      radius: frame.radius
      blur: root.shadow
      offset.y: Style.space(4)
      color: Qt.rgba(0, 0, 0, 0.6)
    }

    Rectangle {
      id: frame
      anchors.centerIn: parent
      width: Style.space(640)
      height: Math.min(view.implicitHeight, (win.screen ? win.screen.height : 900) - Style.space(80))
      radius: root.radius
      color: Color.menu.background
      border.width: Style.normalBorderWidth
      border.color: Util.alpha(Color.foreground, 0.14)
      focus: true
      Keys.onEscapePressed: root.close()

      // Swallow clicks so they do not reach the dismiss area behind the card.
      MouseArea { anchors.fill: parent }

      ManagerView {
        id: view
        anchors.fill: parent
        svc: root
      }
    }
  }
}

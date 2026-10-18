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
import Quickshell.Hyprland
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
  // The settings window floats over the manager rather than replacing it.
  property bool setupOpen: false
  readonly property bool settingsOverlay: root.setupOpen && root.integLoaded
  function closeSetup() { root.setupOpen = false; Qt.callLater(function () { managerView.focusList() }) }
  function closeOverlay() { root.closeSetup() }

  // ---- the filesystem ------------------------------------------------------------------
  property var status: Model.parseStatus("")
  readonly property string health: Model.health(root.status)
  property bool loaded: false               // the first read has finished, so the window never opens empty
  property bool busy: false                 // a setting is being applied
  property string notice: ""
  property bool noticeIsError: false
  property string lastKey: ""               // the node setting the notice is about

  function refresh() { if (!statusProc.running) statusProc.running = true }

  // The window reads fast while it is open; the bar icon needs only a slow look.
  Timer { interval: root.shown ? 5000 : 30000; running: true; repeat: true; onTriggered: root.refresh() }

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
    root.lastKey = key
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
  function focusedScreen() {
    var focus = Hyprland.focusedMonitor
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) if (focus && screens[i].name === focus.name) return screens[i]
    return screens.length ? screens[0] : null
  }
  function show() {
    root.setupOpen = false
    root.targetScreen = root.focusedScreen()
    root.refresh()
    root.shown = true
    Qt.callLater(function () { managerView.focusList() })
  }
  function close() { root.setupOpen = false; root.shown = false }
  // The manager stays behind the settings window: opened first when it was not already showing.
  function showSetup() {
    root.integLoaded = false
    if (!root.shown) { root.targetScreen = root.focusedScreen(); root.refresh(); root.shown = true }
    root.setupOpen = true
    integProc.running = true
  }
  function skipSetup() { skipProc.running = true; root.closeSetup() }
  IpcHandler {
    target: "io.github.bmaltais.startfsgui"
    function state(): string { return JSON.stringify(root.status) }
    function refresh(): string { root.refresh(); return "ok" }
    function open(): void { if (root.shown) root.close(); else root.show() }
    function toggle(): void { if (root.shown) root.close(); else root.show() }
    function close(): void { root.close() }
    function setup(): void { root.showSetup() }
  }

  // ---- the settings: launcher entry, command line, bar icon, window memory -----------------
  property var integ: ({})
  property bool integLoaded: false
  property bool setupBusy: false
  property bool offerSetup: false            // true while the one-time check runs

  // Setup changes go one at a time, in the order they were made; the settings window stays open and reads the
  // real state back once the last one is done.
  property var setupQueue: []
  function applySetting(args) {
    root.setupQueue = root.setupQueue.concat([args])
    root.runNextSetup()
  }
  function runNextSetup() {
    if (setupProc.running) return
    if (root.setupQueue.length === 0) { root.setupBusy = false; integProc.running = true; return }
    root.setupBusy = true
    setupProc.command = [root.cli, "setup"].concat(root.setupQueue[0], ["--json"])
    root.setupQueue = root.setupQueue.slice(1)
    setupProc.running = true
  }

  Process {
    id: integProc
    command: [root.cli, "integration"]
    stdout: StdioCollector {
      onStreamFinished: {
        var info = ({})
        try { info = JSON.parse(text) } catch (e) {}
        root.integ = info
        // The one-time offer only opens the window when setup has not been answered yet.
        if (root.offerSetup) {
          root.offerSetup = false
          if (info.cli && !info.done) { root.showSetup(); return }
        }
        root.integLoaded = true
      }
    }
  }
  Process { id: skipProc; command: [root.cli, "setup", "--done"] }
  Process {
    id: setupProc
    property string last: ""
    // stdout is {ok} or {ok: false, field, error}; a failure the CLI could not put in JSON is a plain stderr line.
    stdout: SplitParser {
      onRead: line => { try { var r = JSON.parse(line); if (!r.ok) setupProc.last = r.error } catch (e) {} }
    }
    stderr: SplitParser { onRead: line => { if (setupProc.last === "") setupProc.last = line.replace(/^startfsgui: /, "") } }
    onStarted: setupProc.last = ""
    onExited: (code, exitStatus) => {
      // A change that failed is said as a notification; reading the state back flips its switch back.
      if (code !== 0) Quickshell.execDetached(["notify-send", "-a", "StartFS", "-u", "critical", "Setting was not applied",
        setupProc.last !== "" ? setupProc.last : "exit code " + code])
      root.runNextSetup()
    }
  }

  // The size and place the windows were last left at.
  Process {
    running: true
    command: [root.cli, "window"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var w = JSON.parse(text)
          win.sizeW = w.w > 0 ? w.w : 0
          win.sizeH = w.h > 0 ? w.h : 0
          win.dragX = w.x
          win.dragY = w.y
          win.sSizeW = w.setup.w > 0 ? w.setup.w : 0
          win.sSizeH = w.setup.h > 0 ? w.setup.h : 0
          win.sDragX = w.setup.x
          win.sDragY = w.setup.y
        } catch (e) {}
      }
    }
  }

  // Once the shell has settled, read the settings: they say whether to offer setup, and what to remember.
  Timer { interval: 4000; running: true; onTriggered: { root.offerSetup = true; integProc.running = true } }
  Component.onCompleted: { root.refresh(); integProc.running = true }
  // The values and their defaults come from `startfsgui integration`; until it has been read, remember.
  readonly property bool rememberSize: root.integ.defaults ? root.integ.rememberSize : true
  readonly property bool rememberPosition: root.integ.defaults ? root.integ.rememberPosition : true

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
    // The card opens centred; dragging its top strip moves it. The offsets are from
    // the centre, so the card stays where it was put when its size changes.
    property real dragX: 0
    property real dragY: 0
    // Where the card was last left is remembered across restarts (see `startfsgui window`);
    // opening it again puts it back, kept on the screen in case the screen has changed.
    // (The window has no size until it is shown, so the check waits for one.)
    onHeightChanged: if (visible) { win.moveBy(0, 0); win.moveSetupBy(0, 0) }
    onVisibleChanged: {
      if (!visible) { win.slow = false; return }
      if (!root.rememberPosition) { win.dragX = 0; win.dragY = 0; win.sDragX = 0; win.sDragY = 0 }
      if (!root.rememberSize) { win.sizeW = 0; win.sizeH = 0; win.sSizeW = 0; win.sSizeH = 0 }
    }

    // The settings window moves and resizes the same way, with its own offsets and size.
    property real sDragX: 0
    property real sDragY: 0
    property real sSizeW: 0
    property real sSizeH: 0
    function saveSetupWindow(withSize) {
      var args = [root.cli, "window"]
      if (root.rememberPosition) args.push("--setup-offset", Math.round(win.sDragX) + "," + Math.round(win.sDragY))
      if (withSize && root.rememberSize && win.sSizeW > 0) args.push("--setup-size", Math.round(win.sSizeW) + "x" + Math.round(win.sSizeH))
      if (args.length > 2) Quickshell.execDetached(args)
    }
    function resetSetupWindow() {
      win.sSizeW = 0; win.sSizeH = 0; win.sDragX = 0; win.sDragY = 0
      Quickshell.execDetached([root.cli, "window", "--reset-setup"])
    }
    function resizeSetupBy(dx, dy) {
      var w = Math.max(Style.space(560), Math.min(win.width - Style.space(40), setupFrame.width + dx))
      var h = Math.max(Style.space(360), Math.min(win.height - Style.space(40), setupFrame.height + dy))
      win.sDragX += (w - setupFrame.width) / 2
      win.sDragY += (h - setupFrame.height) / 2
      win.sSizeW = w
      win.sSizeH = h
    }
    function moveSetupBy(dx, dy) {
      if (win.width <= 0 || win.height <= 0) return
      var grab = Style.space(60)
      var maxX = (win.width + setupFrame.width) / 2 - grab
      var minY = -(win.height - setupFrame.height) / 2
      var maxY = (win.height + setupFrame.height) / 2 - grab
      win.sDragX = Math.max(-maxX, Math.min(maxX, win.sDragX + dx))
      win.sDragY = Math.max(minY, Math.min(maxY, win.sDragY + dy))
    }

    function saveWindow(withSize) {
      var args = [root.cli, "window"]
      if (root.rememberPosition) args.push("--offset", Math.round(win.dragX) + "," + Math.round(win.dragY))
      if (withSize && root.rememberSize && win.sizeW > 0) args.push("--size", Math.round(win.sizeW) + "x" + Math.round(win.sizeH))
      if (args.length > 2) Quickshell.execDetached(args)
    }
    function resetWindow() {
      win.sizeW = 0; win.sizeH = 0; win.dragX = 0; win.dragY = 0
      Quickshell.execDetached([root.cli, "window", "--reset"])
    }
    // The manager can be resized from its bottom-right corner. 0 means the default size.
    property real sizeW: 0
    property real sizeH: 0
    // The top-left corner stays put: the card is centred plus an offset, so a change of
    // size moves the centre by half of it.
    function resizeBy(dx, dy) {
      var w = Math.max(Style.space(480), Math.min(win.width - Style.space(40), frame.width + dx))
      var h = Math.max(Style.space(300), Math.min(win.height - Style.space(40), frame.height + dy))
      win.dragX += (w - frame.width) / 2
      win.dragY += (h - frame.height) / 2
      win.sizeW = w
      win.sizeH = h
    }
    // Keeps the card on the screen: at least the top strip stays reachable.
    function moveBy(dx, dy) {
      if (win.width <= 0 || win.height <= 0) return
      var grab = Style.space(60)
      var maxX = (win.width + frame.width) / 2 - grab
      var minY = -(win.height - frame.height) / 2
      var maxY = (win.height + frame.height) / 2 - grab
      win.dragX = Math.max(-maxX, Math.min(maxX, win.dragX + dx))
      win.dragY = Math.max(minY, Math.min(maxY, win.dragY + dy))
    }

    // Click outside the card to dismiss it.
    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
      MouseArea { anchors.fill: parent; onClicked: { if (root.settingsOverlay) root.closeOverlay(); else root.close() } }
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
      anchors.horizontalCenterOffset: win.dragX
      anchors.verticalCenterOffset: win.dragY
      width: win.sizeW > 0 ? win.sizeW : Style.space(640)
      height: win.sizeH > 0 ? win.sizeH
        : Math.max(Style.space(300), Math.min(managerView.implicitHeight, Style.space(580), (win.screen ? win.screen.height : 900) - Style.space(80)))
      radius: root.radius
      color: Color.menu.background
      border.width: Style.normalBorderWidth
      border.color: Util.alpha(Color.foreground, 0.14)
      focus: true
      Keys.onEscapePressed: root.close()

      // Swallow clicks so they do not reach the dismiss area behind the card.
      MouseArea { anchors.fill: parent }

      // Drag the top strip to move the card. The card moves with the pointer, so the
      // pointer's place on it stays put and each move is the distance from the press.
      // Declared before the view so its own buttons sit above it.
      MouseArea {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Style.space(60)
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        property real pressX: 0
        property real pressY: 0
        onPressed: function (mouse) { pressX = mouse.x; pressY = mouse.y }
        onPositionChanged: function (mouse) {
          if (pressed) win.moveBy(mouse.x - pressX, mouse.y - pressY)
        }
        onReleased: win.saveWindow(false)
      }

      ManagerView {
        id: managerView
        anchors.fill: parent
        svc: root
      }

      // Resize handle in the bottom-right corner: a small grip and a resize pointer.
      MouseArea {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: Style.space(22)
        height: Style.space(22)
        z: 10
        cursorShape: Qt.SizeFDiagCursor
        property real pressX: 0
        property real pressY: 0
        onPressed: function (mouse) { pressX = mouse.x; pressY = mouse.y }
        onPositionChanged: function (mouse) {
          if (pressed) win.resizeBy(mouse.x - pressX, mouse.y - pressY)
        }
        onReleased: win.saveWindow(true)
        onDoubleClicked: win.resetWindow()
        Repeater {
          model: [0, 1]
          Rectangle {
            width: Style.space(10) - index * Style.space(5)
            height: Math.max(1, Style.normalBorderWidth)
            radius: height / 2
            color: Util.alpha(Color.foreground, 0.30)
            rotation: -45
            x: parent.width - Style.space(14) + index * Style.space(5)
            y: parent.height - Style.space(9) - index * Style.space(5) + Style.space(1)
            transformOrigin: Item.Center
          }
        }
      }

      // Close button in the card's top-right corner.
      Button {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Style.spacing.lg
        anchors.rightMargin: Style.spacing.lg
        z: 10
        iconText: ""
        tooltipText: "Close"
        onClicked: root.close()
      }
    }

    // ---- the settings window, over the manager ------------------------------------------
    // The manager stays where it is, dimmed; closing the settings brings it back.
    Rectangle {
      visible: root.settingsOverlay
      anchors.fill: frame
      radius: frame.radius
      color: Qt.rgba(0, 0, 0, 0.35)
      MouseArea { anchors.fill: parent; onClicked: root.closeOverlay() }
    }

    RectangularShadow {
      visible: setupFrame.visible
      anchors.fill: setupFrame
      radius: setupFrame.radius
      blur: root.shadow
      offset.y: Style.space(4)
      color: Qt.rgba(0, 0, 0, 0.6)
    }

    Rectangle {
      id: setupFrame
      visible: root.settingsOverlay
      anchors.centerIn: parent
      anchors.horizontalCenterOffset: win.sDragX
      anchors.verticalCenterOffset: win.sDragY
      width: win.sSizeW > 0 ? win.sSizeW : Style.space(760)
      height: win.sSizeH > 0 ? win.sSizeH : Math.min(setupLoader.item ? (setupLoader.item as Item).implicitHeight : 0, (win.screen ? win.screen.height : 900) - Style.space(80))
      radius: root.radius
      color: Color.menu.background
      border.width: Style.normalBorderWidth
      border.color: Util.alpha(Color.foreground, 0.14)
      focus: true
      Keys.onEscapePressed: root.closeOverlay()
      onVisibleChanged: if (visible) setupFrame.forceActiveFocus()

      // Swallow clicks so they do not reach the dismiss area behind the card.
      MouseArea { anchors.fill: parent }

      // Drag the top strip to move the window; declared before the content so its own
      // search box and buttons sit above it.
      MouseArea {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Style.space(60)
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        property real pressX: 0
        property real pressY: 0
        onPressed: function (mouse) { pressX = mouse.x; pressY = mouse.y }
        onPositionChanged: function (mouse) {
          if (pressed) win.moveSetupBy(mouse.x - pressX, mouse.y - pressY)
        }
        onReleased: win.saveSetupWindow(false)
      }

      // Built only while open: a closed view would still hold its text inputs, and Qt reads the
      // clipboard for each of them on every clipboard change.
      Loader {
        id: setupLoader
        property var owner: root
        anchors.fill: parent
        active: root.setupOpen
        sourceComponent: SetupView { svc: setupLoader.owner }
      }

      // Resize handle in the bottom-right corner, as on the manager.
      MouseArea {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: Style.space(22)
        height: Style.space(22)
        z: 10
        cursorShape: Qt.SizeFDiagCursor
        property real pressX: 0
        property real pressY: 0
        onPressed: function (mouse) { pressX = mouse.x; pressY = mouse.y }
        onPositionChanged: function (mouse) {
          if (pressed) win.resizeSetupBy(mouse.x - pressX, mouse.y - pressY)
        }
        onReleased: win.saveSetupWindow(true)
        onDoubleClicked: win.resetSetupWindow()
        Repeater {
          model: [0, 1]
          Rectangle {
            width: Style.space(10) - index * Style.space(5)
            height: Math.max(1, Style.normalBorderWidth)
            radius: height / 2
            color: Util.alpha(Color.foreground, 0.30)
            rotation: -45
            x: parent.width - Style.space(14) + index * Style.space(5)
            y: parent.height - Style.space(9) - index * Style.space(5) + Style.space(1)
            transformOrigin: Item.Center
          }
        }
      }

      Button {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Style.spacing.lg
        anchors.rightMargin: Style.spacing.lg
        z: 10
        iconText: ""
        tooltipText: "Close"
        onClicked: root.closeOverlay()
      }
    }
  }
}

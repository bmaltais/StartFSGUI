// The manager: is the data safe, who is in the filesystem, and what needs attention.
// Keyboard: Up/Down (or j/k) pick a node, u updates it (press twice), r looks again, s opens the settings, Esc closes.
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "StartFSModel.js" as Model

FocusScope {
  id: view

  property var svc
  readonly property var st: view.svc.status
  readonly property bool degraded: view.svc.health !== "safe"

  implicitHeight: col.implicitHeight + Style.spacing.panelPadding * 2
  // The numbers under the header. The storage lines come from builds that report where the space went; an older one just has none.
  readonly property var facts: {
    var s = view.st
    var o = s.storage
    var f = [
      ["FILESYSTEM", s.fs + " (" + s.copies + " copies)"],
      ["COPIES POSSIBLE", s.possible + " of " + s.wanted + " on " + s.nodes + " nodes"]
    ]
    if (o) {
      f.push(["IN FILES", o.files])
      f.push(["AFTER DEDUP", o.afterDedup + (o.dedup !== "" ? "  (" + o.dedup + ")" : "")])
    }
    f.push(["STORED", s.stored], ["USABLE", s.usable])
    if (o) f.push(["THIS NODE", o.nodeDisk + " on disk" + (o.compression !== "" ? ", compression " + o.compression : "")
      + (o.share !== "" ? ", " + o.share + " of the replicas" : ""), true])
    f.push(["CACHE", s.cache], ["SCRUB", s.scrub])
    return f
  }
  // What a member's row says about its space: its use of what it offers once asked, else just what it offers.
  function spaceText(m) {
    var n = view.svc.nodeStats[m.host]
    if (n === undefined) return m.offered
    return n.answered ? n.disk + " of " + n.offered : "no answer"
  }
  readonly property var attention: {
    var out = []
    var s = view.st
    if (!s.ok) return out
    if (s.repair) out.push({ bad: false, text: "Repairing: " + s.repair.atRisk + " chunks at risk, " + s.repair.degraded + " degraded." })
    else if (s.unreplicated > 0) out.push({ bad: false, text: s.unreplicated + " chunks are not fully replicated yet." })
    if (s.staging !== "") out.push({ bad: false, text: "Waiting for replication: " + s.staging + "." })
    s.warnings.forEach(function (w) { out.push({ bad: true, text: w }) })
    if (s.conflicts.length > 0) out.push({ bad: true, text: s.conflicts.length + " conflict " + (s.conflicts.length === 1 ? "copy" : "copies") + ": delete one of each pair to resolve it." })
    s.members.forEach(function (mb) { if (mb.problem !== "") out.push({ bad: true, text: mb.host + " cannot be reached: " + mb.problem }) })
    return out
  }
  property int cursor: 0
  readonly property var member: view.st.members.length ? view.st.members[Math.min(view.cursor, view.st.members.length - 1)] : null
  property bool confirming: false
  function move(dy) { view.cursor = Math.max(0, Math.min(view.st.members.length - 1, view.cursor + dy)); view.confirming = false }
  // Two presses to upgrade: the first asks, the second goes. It lapses after three seconds.
  function askUpdate() {
    if (!view.member || view.svc.updating) return
    if (view.confirming) { view.confirming = false; confirmTimer.stop(); view.svc.update(view.member, versionField.text.trim()) }
    else { view.confirming = true; confirmTimer.restart() }
  }
  Timer { id: confirmTimer; interval: 3000; onTriggered: view.confirming = false }
  readonly property bool versionOk: versionField.text.trim() === "" || /^v[0-9]+\.[0-9]+\.[0-9]+$/.test(versionField.text.trim())
  function versionText(m) {
    var v = view.svc.versions[m.host]
    if (v === undefined) return m.state === "up" || m.self ? "…" : "down"
    return v.error !== undefined ? "unknown" : v.version
  }
  function focusList() { view.forceActiveFocus() }
  onVisibleChanged: if (visible) { view.cursor = 0; view.confirming = false; view.forceActiveFocus() }

  Keys.onPressed: event => {
    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
    // Typing in the release box is not a command.
    if (versionField.focused) return
    if (event.key === Qt.Key_Up || event.text === "k") { view.move(-1); event.accepted = true }
    else if (event.key === Qt.Key_Down || event.text === "j") { view.move(1); event.accepted = true }
    else if (event.text === "u") { if (view.versionOk) view.askUpdate(); event.accepted = true }
    else if (event.text === "r") { view.svc.refresh(); view.svc.refreshStats(); view.svc.checkVersions(true); event.accepted = true }
    else if (event.text === "s") { view.svc.showSetup(); event.accepted = true }
  }

  ColumnLayout {
    id: col
    anchors.fill: parent
    anchors.margins: Style.spacing.panelPadding
    spacing: Style.spacing.panelGap

    // Header
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.xxl

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        Text {
          text: "StartFS"
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.heading
          font.bold: true
        }
        Text {
          Layout.fillWidth: true
          elide: Text.ElideRight
          text: Model.headline(view.st).toUpperCase()
          color: view.degraded ? Color.urgent : Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1
        }
      }
      Button {
        iconText: ""
        tooltipText: "Look again  (r)"
        iconSpinning: spin.running
        onClicked: { spin.restart(); view.svc.refresh(); view.svc.refreshStats(); view.svc.checkVersions(true) }
        Timer { id: spin; interval: 900 }
      }
      Button {
        iconText: ""
        tooltipText: "Settings  (s)"
        onClicked: view.svc.showSetup()
      }
      // Keeps clear of the close button in the card's corner.
      Item { Layout.preferredWidth: Style.space(24) }
    }

    // The numbers
    GridLayout {
      Layout.fillWidth: true
      visible: view.st.ok
      columns: 2
      columnSpacing: Style.spacing.xxl
      rowSpacing: Style.spacing.md
      Repeater {
        model: view.facts
        delegate: ColumnLayout {
          required property var modelData
          Layout.fillWidth: true
          // A long line takes the whole row.
          Layout.columnSpan: modelData[2] ? 2 : 1
          spacing: 0
          Text { text: modelData[0]; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption; font.letterSpacing: 1 }
          Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: modelData[1]
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
        }
      }
    }

    // What needs attention, only when there is something.
    Repeater {
      model: view.attention
      delegate: Text {
        required property var modelData
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: modelData.text
        color: modelData.bad ? Color.urgent : Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }

    Text {
      Layout.fillWidth: true
      visible: !view.st.ok
      wrapMode: Text.WordWrap
      text: "Start it with:  systemctl --user start startfs"
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    // Members
    Text {
      visible: view.st.members.length > 0
      text: "MEMBERS"
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.letterSpacing: 1
    }
    Repeater {
      model: view.st.members
      delegate: Rectangle {
        required property var modelData
        required property int index
        Layout.fillWidth: true
        implicitHeight: row.implicitHeight + Style.space(6)
        radius: Math.max(Style.cornerRadius, Style.space(5))
        color: index === view.cursor ? Util.alpha(Color.accent, 0.18) : (hover.hovered ? Util.alpha(Color.foreground, 0.06) : "transparent")
        HoverHandler { id: hover }
        MouseArea { anchors.fill: parent; onClicked: { view.cursor = index; view.confirming = false; view.forceActiveFocus() } }
        RowLayout {
          id: row
          anchors.fill: parent
          anchors.leftMargin: Style.spacing.xxl
          anchors.rightMargin: Style.spacing.xxl
          spacing: Style.spacing.xxl
          Rectangle {
            Layout.preferredWidth: Style.space(8)
            Layout.preferredHeight: Style.space(8)
            radius: width / 2
            color: modelData.state === "up" ? Color.accent : Color.urgent
          }
          Text {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: modelData.host + (modelData.self ? "  (this node)" : "")
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
          // Fixed columns, so the versions and the sizes line up down the list; values are read at full strength, not muted.
          Text {
            Layout.preferredWidth: Style.space(56)
            horizontalAlignment: Text.AlignRight
            text: view.versionText(modelData)
            color: view.versionText(modelData) === "unknown" ? Color.urgent : Util.alpha(Color.foreground, 0.85)
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
          Text {
            Layout.preferredWidth: Style.space(170)
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideLeft
            text: view.spaceText(modelData)
            color: Util.alpha(Color.foreground, 0.85)
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
        }
      }
    }

    // Upgrade the picked node: StartFS's own installer, over ssh (or here, for this node).
    RowLayout {
      Layout.fillWidth: true
      visible: view.member !== null
      spacing: Style.spacing.xxl
      Field {
        id: versionField
        Layout.preferredWidth: Style.space(150)
        placeholder: "latest (or v1.0.7)"
        onEscaped: text = ""
      }
      Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        readonly property var v: view.member ? view.svc.versions[view.member.host] : undefined
        readonly property bool bad: v !== undefined && v.error !== undefined
        text: {
          if (!view.member) return ""
          if (view.confirming) return view.member.self
            ? "Press u again. The daemon restarts and the mount drops for a few seconds."
            : "Press u again to update " + view.member.host + "."
          if (bad) return view.member.host + " could not be asked: " + v.error
          return view.member.self ? "Update this node last: its mount drops while the daemon restarts." : "Updates over ssh with StartFS's installer."
        }
        color: bad ? Color.urgent : Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
      Button {
        text: view.confirming ? "Click again to update" : (view.svc.updating ? "Updating…" : "Update")
        bordered: true
        enabled: view.member !== null && !view.svc.updating && view.versionOk
        tooltipText: "Run StartFS's installer on this node  (u)"
        onClicked: view.askUpdate()
      }
    }
    // The installer's own words while it runs, and what it said last: one line each, cut off at the card's edge, so the box has
    // a height that does not depend on how long the installer's sentences are.
    Rectangle {
      Layout.fillWidth: true
      visible: view.svc.updateLines.length > 0
      implicitHeight: logCol.implicitHeight + Style.space(16)
      radius: Math.max(Style.cornerRadius, Style.space(5))
      color: Util.alpha(Color.foreground, 0.06)
      clip: true
      ColumnLayout {
        id: logCol
        anchors.fill: parent
        anchors.margins: Style.space(8)
        spacing: 0
        Text {
          Layout.fillWidth: true
          elide: Text.ElideRight
          text: view.svc.updateHost
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }
        Repeater {
          model: view.svc.updateLines
          delegate: Text {
            required property string modelData
            Layout.fillWidth: true
            elide: Text.ElideRight
            maximumLineCount: 1
            text: modelData
            color: view.svc.updateFailed ? Color.urgent : Util.alpha(Color.foreground, 0.8)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
    }

    // Footer
    Text {
      Layout.fillWidth: true
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideRight
      text: view.svc.notice !== "" ? view.svc.notice : "Esc to close"
      color: view.svc.notice !== "" && view.svc.noticeIsError ? Color.urgent : Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }
  }
}

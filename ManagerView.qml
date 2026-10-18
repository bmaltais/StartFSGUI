// The manager: is the data safe, who is in the filesystem, and what needs attention.
// Keyboard: r looks again, s opens the settings, Esc closes.
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
  function focusList() { view.forceActiveFocus() }
  onVisibleChanged: if (visible) view.forceActiveFocus()

  Keys.onPressed: event => {
    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
    if (event.text === "r") { view.svc.refresh(); event.accepted = true }
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
        onClicked: { spin.restart(); view.svc.refresh() }
        Timer { id: spin; interval: 900 }
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
        model: [
          ["FILESYSTEM", view.st.fs + " (" + view.st.copies + " copies)"],
          ["COPIES POSSIBLE", view.st.possible + " of " + view.st.wanted + " on " + view.st.nodes + " nodes"],
          ["STORED", view.st.stored],
          ["USABLE", view.st.usable],
          ["CACHE", view.st.cache],
          ["SCRUB", view.st.scrub]
        ]
        delegate: ColumnLayout {
          required property var modelData
          Layout.fillWidth: true
          spacing: 0
          Text { text: modelData[0]; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption; font.letterSpacing: 1 }
          Text { text: modelData[1]; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body }
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
      delegate: RowLayout {
        required property var modelData
        Layout.fillWidth: true
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
        Text { text: modelData.offered; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
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

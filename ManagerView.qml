// The manager: is the data safe, who is in the filesystem, and this node's two settings (space offered, copies).
// Keyboard: r refreshes, Esc closes.
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
  // The box follows the daemon's value until the user is typing in it.
  function syncOffer() { if (!offerField.focused) offerField.text = view.st.offered.replace(/\s+/g, "") }
  onStChanged: view.syncOffer()
  onVisibleChanged: if (visible) { view.syncOffer(); view.forceActiveFocus() }

  Keys.onPressed: event => {
    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
    if (event.text === "r") { view.svc.refresh(); event.accepted = true }
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

    // This node's settings
    Text {
      visible: view.st.ok
      text: "THIS NODE"
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.letterSpacing: 1
    }
    RowLayout {
      Layout.fillWidth: true
      visible: view.st.ok
      spacing: Style.spacing.xxl
      Text { text: "Space offered"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body }
      Field {
        id: offerField
        Layout.fillWidth: true
        placeholder: "500G"
        onAccepted: if (Model.validSize(text)) view.svc.apply("offer", text.trim())
      }
      Button {
        text: "Apply"
        bordered: true
        enabled: !view.svc.busy && Model.validSize(offerField.text)
        onClicked: view.svc.apply("offer", offerField.text.trim())
      }
    }
    RowLayout {
      Layout.fillWidth: true
      visible: view.st.ok
      spacing: Style.spacing.md
      Text { text: "Copies of every file"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.body }
      Item { Layout.fillWidth: true }
      Repeater {
        model: [1, 2, 3, 4, 5]
        delegate: Chip {
          required property int modelData
          label: String(modelData)
          selected: modelData === view.st.copies
          onClicked: if (!view.svc.busy && modelData !== view.st.copies) view.svc.apply("copies", modelData)
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

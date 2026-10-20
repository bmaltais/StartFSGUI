// One member of the filesystem, the way StartAppImage shows one app: a tile, its name and tags, a status line, how full its offer
// is, and its actions (details, settings, and remove when it is gone).
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "StartFSModel.js" as Model

Rectangle {
  id: row

  property var member: ({})
  property var stats: undefined              // its `startfs stats` figures, once read
  property string target: ""                 // the release an upgrade is moving to, if one is running
  property string release: ""                // the release most nodes run
  property bool current: false
  property bool busy: false
  property bool confirming: false

  signal detailsRequested()
  signal settingsRequested()
  signal removeRequested()
  signal forceRequested()
  signal selectRequested()

  // Only a member that is gone can be removed; a live one leaves by itself (from its own settings).
  readonly property bool removable: row.member.state === "down" || row.member.state === "lost"
  function askRemove() { if (row.removable) row.confirming = true }

  readonly property string tone: Model.stateTone(row.member)
  readonly property bool bad: row.tone === "bad"
  readonly property bool hot: hover.hovered || row.current
  readonly property real fill: Model.fill(row.member, row.stats)
  readonly property string line: Model.memberLine(row.member, row.stats, row.target)
  // Tags beside the name: this node, and any state other than up.
  readonly property var tags: {
    var t = []
    var m = row.member
    if (m.self) t.push({ text: "THIS NODE", loud: false })
    if (m.state !== "up") t.push({ text: m.state === "upgrading" ? "RESTARTING" : String(m.state).toUpperCase(), loud: row.bad })
    if (m.state === "up" && m.behind) t.push({ text: "BEHIND", loud: true })
    if (m.upgradeStep === "failed") t.push({ text: "UPGRADE FAILED", loud: true })
    else if (m.upgradeStep === "" && m.release !== "" && Model.compareRelease(m.release, row.release) < 0) t.push({ text: "OLDER RELEASE", loud: false })
    return t
  }

  implicitHeight: Style.space(62)
  radius: Math.max(Style.cornerRadius, Style.space(6))
  color: Util.alpha(Color.foreground, row.hot ? 0.10 : 0.05)
  border.width: Style.normalBorderWidth
  border.color: row.current ? Util.alpha(Color.accent, 0.7) : row.bad ? Util.alpha(Color.urgent, 0.45) : Util.alpha(Color.foreground, 0.06)

  HoverHandler { id: hover }
  // A click anywhere on the row, buttons included, makes it the highlighted one; a double click opens its details.
  TapHandler { onTapped: row.selectRequested(); onDoubleTapped: row.detailsRequested() }
  onConfirmingChanged: if (!confirming) confirmTimer.stop(); else confirmTimer.restart()
  Timer { id: confirmTimer; interval: 4000; onTriggered: row.confirming = false }

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: Style.spacing.xxl
    anchors.rightMargin: Style.spacing.lg
    spacing: Style.spacing.xxl

    // The tile: a desktop for this node, a server for the others, red when it cannot be reached.
    Rectangle {
      Layout.preferredWidth: Style.space(36)
      Layout.preferredHeight: Style.space(36)
      radius: Style.space(8)
      color: row.bad ? Util.alpha(Color.urgent, 0.18) : Util.alpha(Color.foreground, row.member.self ? 0.14 : 0.08)
      Text {
        textFormat: Text.PlainText
        anchors.centerIn: parent
        text: row.member.self ? "" : ""
        color: row.bad ? Color.urgent : Util.alpha(Color.foreground, row.member.state === "up" ? 0.9 : 0.5)
        font.family: Style.font.family
        font.pixelSize: Style.font.title
      }
      // Pulses while the member is restarting for an upgrade.
      SequentialAnimation on opacity {
        running: row.member.state === "upgrading" || row.member.upgradeStep === "restarting"
        loops: Animation.Infinite
        alwaysRunToEnd: true
        NumberAnimation { to: 0.45; duration: 600 }
        NumberAnimation { to: 1; duration: 600 }
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.xxs
      RowLayout {
        id: nameRow
        Layout.fillWidth: true
        spacing: Style.spacing.lg
        Text {
          textFormat: Text.PlainText
          Layout.maximumWidth: nameRow.width - tagRow.width - nameRow.spacing
          text: row.member.host || ""
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
          font.bold: true
          elide: Text.ElideRight
        }
        Row {
          id: tagRow
          spacing: Style.spacing.md
          Repeater {
            model: row.tags
            delegate: Rectangle {
              required property var modelData
              implicitWidth: tagText.implicitWidth + Style.space(10)
              implicitHeight: tagText.implicitHeight + Style.space(4)
              radius: Style.space(4)
              color: "transparent"
              border.width: Style.normalBorderWidth
              border.color: modelData.loud ? Util.alpha(Color.urgent, 0.6) : Util.alpha(Color.foreground, 0.30)
              Text {
                id: tagText
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: modelData.text
                color: modelData.loud ? Color.urgent : Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
              }
            }
          }
        }
        Item { Layout.fillWidth: true }
      }
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.spacing.md
        Rectangle {
          Layout.preferredWidth: Style.space(7)
          Layout.preferredHeight: Style.space(7)
          radius: width / 2
          color: row.bad ? Color.urgent : row.tone === "warn" ? Util.alpha(Color.urgent, 0.6)
            : Model.stepActive(row.member) ? Color.accent : Util.alpha(Color.foreground, 0.35)
        }
        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          color: row.bad ? Color.urgent : Model.stepActive(row.member) ? Color.accent : Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
          text: row.busy ? "Working..." : row.line
        }
      }
    }

    // How full its offer is, once `stats` has answered: a percentage over a thin bar, the same width on every row.
    ColumnLayout {
      Layout.preferredWidth: Style.space(72)
      visible: !row.confirming && row.fill >= 0
      spacing: Style.spacing.xs
      Text {
        textFormat: Text.PlainText
        Layout.alignment: Qt.AlignRight
        text: Math.round(row.fill * 100) + "%"
        color: Util.alpha(Color.foreground, 0.8)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Style.space(4)
        radius: height / 2
        color: Util.alpha(Color.foreground, 0.10)
        Rectangle {
          width: Math.max(parent.height, parent.width * row.fill)
          height: parent.height
          radius: height / 2
          color: row.fill > 0.9 ? Color.urgent : Util.alpha(Color.foreground, 0.55)
        }
      }
    }
    // Keeps the actions lined up on rows that have no figures.
    Item { Layout.preferredWidth: Style.space(72); visible: !row.confirming && row.fill < 0 }

    // Actions
    RowLayout {
      spacing: Style.spacing.md
      visible: !row.confirming && !row.busy

      // This node staged the release but its mount is in use: the one thing to do.
      Button {
        visible: row.member.self && row.member.upgradeStep === "waiting on mount"
        text: "Restart now"
        selected: true
        tooltipText: "Restart on the new release though files on the mount are open"
        onClicked: row.forceRequested()
      }
      Button {
        iconText: ""
        tooltipText: "Details  (Enter)"
        onClicked: row.detailsRequested()
      }
      Button {
        iconText: ""
        tooltipText: "Settings"
        onClicked: row.settingsRequested()
      }
      Button {
        visible: row.removable
        iconText: ""
        tooltipText: "Remove from the filesystem  (Delete)"
        onClicked: row.confirming = true
      }
    }

    RowLayout {
      spacing: Style.spacing.md
      visible: row.confirming && !row.busy
      Text {
        textFormat: Text.PlainText
        text: "Remove " + row.member.host + "?"
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
      Button {
        text: "Remove"
        bordered: true
        foreground: Color.urgent
        onClicked: { row.confirming = false; row.removeRequested() }
      }
      Button {
        text: "No"
        bordered: true
        onClicked: row.confirming = false
      }
    }
  }
}

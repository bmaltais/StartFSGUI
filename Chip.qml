// A small selectable choice: a folder, "Shown"/"Hidden", and so on.
import QtQuick
import qs.Commons
import qs.Ui

Rectangle {
  id: chip

  property string label: ""
  property bool selected: false
  signal clicked()

  implicitWidth: chipLabel.implicitWidth + Style.space(18)
  implicitHeight: chipLabel.implicitHeight + Style.space(10)
  radius: Math.max(Style.cornerRadius, Style.space(5))
  color: selected ? Util.alpha(Color.accent, 0.18) : Util.alpha(Color.foreground, chipHover.hovered ? 0.10 : 0.04)
  border.width: Style.normalBorderWidth
  border.color: selected ? Color.accent : Util.alpha(Color.foreground, 0.20)

  HoverHandler { id: chipHover }
  Text {
    textFormat: Text.PlainText
    id: chipLabel
    anchors.centerIn: parent
    text: chip.label
    color: chip.selected ? Color.accent : Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
  }
  MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: chip.clicked() }
}

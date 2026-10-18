// The optional bar icon: a database glyph that is red when the data is not safe. It reads a file the service keeps up to date,
// because the icon and the service are separate instances.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.bmaltais.startfsgui"

  readonly property string statusFile: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/startfsgui/status"
  property string kind: "unknown"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  FileView {
    path: root.statusFile
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: { var k = text().trim(); root.kind = (k === "safe" || k === "degraded") ? k : "unknown" }
    onLoadFailed: root.kind = "unknown"
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    active: root.kind === "degraded"
    useActiveColor: true
    activeColor: Color.urgent
    onPressed: function (mouse) {
      if (!root.bar) return
      if (mouse === Qt.RightButton) root.bar.run("omarchy-shell io.github.bmaltais.startfsgui refresh")
      else root.bar.run("omarchy-shell io.github.bmaltais.startfsgui open")
    }
  }
}

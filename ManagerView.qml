// The manager: is the data safe, and every node of the filesystem as a row, the way StartAppImage lists apps.
// Keyboard: type to search, Up/Down to move, Enter opens a node's details, Delete removes a node that is gone (after a
// confirmation), Ctrl+R looks again, Ctrl+S opens the settings, Esc clears the search and then closes.
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "StartFSModel.js" as Model

Item {
  id: view

  property var svc
  property string query: ""
  property int cursor: 0
  property bool inviting: false

  readonly property var st: view.svc.status
  readonly property bool degraded: view.svc.health !== "safe"
  readonly property var progress: view.svc.progress
  // Sites group the rows when any member declares one; otherwise it is one list.
  readonly property bool bySite: view.st.members.some(function (m) { return m.site !== "" })
  readonly property var rows: {
    var q = view.query.trim().toLowerCase()
    var out = view.st.members.filter(function (m) {
      return q === "" || (m.host + " " + m.site + " " + m.release + " " + m.state).toLowerCase().indexOf(q) !== -1
    })
    // By site, this node first in its site, then by name: the same order on every read, so the cursor does not jump.
    var mine = (view.st.members.filter(function (m) { return m.self })[0] || { site: "" }).site
    return out.slice().sort(function (a, b) {
      // This node's site first, the others by name, members with no site last.
      if (view.bySite && a.site !== b.site) {
        if (a.site === mine || b.site === mine) return a.site === mine ? -1 : 1
        return a.site === "" ? 1 : b.site === "" ? -1 : a.site < b.site ? -1 : 1
      }
      if (a.self !== b.self) return a.self ? -1 : 1
      return a.host < b.host ? -1 : a.host > b.host ? 1 : 0
    })
  }
  readonly property var currentMember: view.rows.length ? view.rows[Math.min(view.cursor, view.rows.length - 1)] : null
  readonly property string subtitle: {
    if (!view.st.ok) return view.svc.loaded ? "NOT RUNNING" : "READING"
    var parts = [view.st.fs.toUpperCase(), view.st.nodes + (view.st.nodes === 1 ? " NODE" : " NODES")]
    var r = Model.clusterRelease(view.st)
    if (r !== "") parts.push(r.toUpperCase())
    return parts.join("  ·  ")
  }
  // A newer StartFS than the cluster runs, and no upgrade under way: the header offers it.
  readonly property bool canUpgrade: view.st.ok && view.progress === null && view.svc.latest !== ""
    && Model.compareRelease(view.svc.latest, Model.clusterRelease(view.st)) > 0
  // What needs attention, said once, under the headline. Members that cannot be reached are said on their own rows.
  readonly property var attention: {
    var out = []
    var s = view.st
    if (!s.ok) return out
    if (s.repair) out.push({ bad: false, text: "Repairing: " + s.repair.atRisk + " chunks at risk, " + s.repair.degraded + " degraded." })
    else if (s.unreplicated > 0) out.push({ bad: false, text: s.unreplicated + " chunks do not have all their copies yet." })
    if (s.stranded.length > 0) out.push({ bad: true, text: s.stranded.reduce(function (n, x) { return n + x.chunks }, 0)
      + " chunks may exist only on a node that is down." })
    if (s.staging !== "") out.push({ bad: false, text: "Waiting for replication: " + s.staging + "." })
    if (s.tickBusy) out.push({ bad: true, text: "This node is overloaded: busy " + s.tickBusy.percent + "% of the last minute." })
    s.warnings.forEach(function (w) { out.push({ bad: true, text: w.charAt(0).toUpperCase() + w.slice(1) + "." }) })
    if (s.conflicts.length > 0) out.push({ bad: true, text: s.conflicts.length + " conflict " + (s.conflicts.length === 1 ? "copy" : "copies")
      + ": delete one of each pair to resolve it." })
    return out
  }

  function move(dy) { view.cursor = Math.max(0, Math.min(view.rows.length - 1, view.cursor + dy)) }
  function focusList() { search.forceActiveFocus() }
  function currentRow() { return list.itemAtIndex(Math.min(view.cursor, Math.max(0, view.rows.length - 1))) }
  function lookAgain() { spin.restart(); view.svc.refreshAll() }

  onVisibleChanged: {
    if (visible) {
      search.text = ""
      view.query = ""
      view.cursor = 0
      view.inviting = false
      search.forceActiveFocus()
    }
  }
  onRowsChanged: view.cursor = Math.max(0, Math.min(view.cursor, view.rows.length - 1))

  implicitHeight: col.implicitHeight + Style.spacing.panelPadding * 2

  ColumnLayout {
    id: col
    anchors.fill: parent
    anchors.margins: Style.spacing.panelPadding
    spacing: Style.spacing.panelGap

    // ---- header ------------------------------------------------------------------------------
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.xxl

      Image {
        source: Qt.resolvedUrl("assets/startfsgui.svg")
        sourceSize.width: Style.space(64)
        sourceSize.height: Style.space(64)
        Layout.preferredWidth: Style.space(32)
        Layout.preferredHeight: Style.space(32)
      }
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        Text {
          textFormat: Text.PlainText
          text: "StartFS"
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.heading
          font.bold: true
        }
        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          elide: Text.ElideRight
          text: view.subtitle
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1
        }
      }
      Button {
        visible: view.canUpgrade
        text: "Upgrade to " + view.svc.latest
        selected: true
        tooltipText: "Every node moves to " + view.svc.latest + ", one at a time"
        onClicked: view.svc.showSetup("Upgrade")
      }
      Button {
        iconText: ""
        tooltipText: "Settings  (Ctrl+S)"
        onClicked: view.svc.showSetup("")
      }
      Button {
        iconText: ""
        tooltipText: "Look again  (Ctrl+R)"
        iconSpinning: spin.running || view.svc.statsBusy
        onClicked: view.lookAgain()
        Timer { id: spin; interval: 900 }
      }
      // Keeps clear of the close button in the card's corner.
      Item { Layout.preferredWidth: Style.space(24) }
    }

    // ---- is the data safe ---------------------------------------------------------------------
    Rectangle {
      id: banner
      Layout.fillWidth: true
      implicitHeight: bannerCol.implicitHeight + Style.spacing.xxl * 2
      radius: Math.max(Style.cornerRadius, Style.space(6))
      color: view.degraded ? Util.alpha(Color.urgent, 0.10) : Util.alpha(Color.foreground, 0.05)
      border.width: Style.normalBorderWidth
      border.color: view.degraded ? Util.alpha(Color.urgent, 0.35) : Util.alpha(Color.foreground, 0.06)

      HoverHandler { id: bannerHover; cursorShape: Qt.PointingHandCursor }
      TapHandler { onTapped: view.svc.showSetup("Overview") }

      ColumnLayout {
        id: bannerCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.spacing.xxl
        anchors.rightMargin: Style.spacing.xxl
        spacing: Style.spacing.md

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.xxl
          // A shield when safe, a warning sign when not, a question when the daemon cannot be asked.
          Text {
            textFormat: Text.PlainText
            text: !view.st.ok ? "" : view.degraded ? "" : ""
            color: view.degraded ? Color.urgent : Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
          }
          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.spacing.xxs
            Text {
              textFormat: Text.PlainText
              Layout.fillWidth: true
              elide: Text.ElideRight
              text: Model.headline(view.st)
              color: view.degraded ? Color.urgent : Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              textFormat: Text.PlainText
              Layout.fillWidth: true
              elide: Text.ElideRight
              text: Model.summary(view.st)
              color: Color.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
          }
          Text {
            textFormat: Text.PlainText
            visible: view.st.ok
            text: "Details  "
            color: bannerHover.hovered ? Color.foreground : Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        // At most three lines of what needs attention, then a count; the rest is in the details.
        Repeater {
          model: view.attention.slice(0, 3)
          delegate: Text {
            required property var modelData
            textFormat: Text.PlainText
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: modelData.text
            color: modelData.bad ? Color.urgent : Util.alpha(Color.foreground, 0.75)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
        }
        Text {
          textFormat: Text.PlainText
          visible: view.attention.length > 3
          text: "and " + (view.attention.length - 3) + " more"
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        // A cluster upgrade under way: how far it is, and what holds it up.
        ColumnLayout {
          Layout.fillWidth: true
          visible: view.progress !== null
          spacing: Style.spacing.sm
          RowLayout {
            Layout.fillWidth: true
            Text {
              textFormat: Text.PlainText
              Layout.fillWidth: true
              elide: Text.ElideRight
              text: view.progress ? view.progress.text : ""
              color: view.progress && view.progress.failed.length ? Color.urgent : Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              textFormat: Text.PlainText
              text: view.progress ? view.progress.done + " of " + view.progress.total : ""
              color: Color.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
          }
          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(4)
            radius: height / 2
            color: Util.alpha(Color.foreground, 0.10)
            Rectangle {
              width: view.progress && view.progress.total > 0 ? parent.width * view.progress.done / view.progress.total : 0
              height: parent.height
              radius: height / 2
              color: view.progress && view.progress.failed.length ? Color.urgent : Color.accent
              Behavior on width { NumberAnimation { duration: 160 } }
            }
          }
        }
      }
    }

    // ---- search ----------------------------------------------------------------------------------
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: Style.space(36)
      visible: view.st.members.length > 0
      radius: height / 2
      color: Util.alpha(Color.foreground, 0.06)
      border.width: Style.normalBorderWidth
      border.color: Util.alpha(Color.foreground, search.activeFocus ? 0.30 : 0.12)

      Text {
        id: glass
        textFormat: Text.PlainText
        anchors.left: parent.left
        anchors.leftMargin: Style.spacing.xxxl
        anchors.verticalCenter: parent.verticalCenter
        text: ""
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
      TextInput {
        id: search
        anchors.left: glass.right
        anchors.leftMargin: Style.spacing.lg
        anchors.right: parent.right
        anchors.rightMargin: Style.spacing.xxxl
        anchors.verticalCenter: parent.verticalCenter
        color: Color.foreground
        selectionColor: Util.alpha(Color.accent, 0.4)
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        clip: true
        // Read-only until focused: an editable TextInput reads the clipboard on every change.
        readOnly: !activeFocus
        onTextChanged: view.query = text

        Keys.onUpPressed: view.move(-1)
        Keys.onDownPressed: view.move(1)
        Keys.onReturnPressed: if (view.currentMember) view.svc.showNode(view.currentMember, "Status")
        Keys.onEnterPressed: if (view.currentMember) view.svc.showNode(view.currentMember, "Status")
        Keys.onPressed: event => {
          if (event.key === Qt.Key_Escape && text !== "") { text = ""; event.accepted = true }
          else if (event.key === Qt.Key_Escape && view.inviting) { view.inviting = false; event.accepted = true }
          else if (event.key === Qt.Key_Delete && text === "" && view.currentMember) { view.currentRow().askRemove(); event.accepted = true }
          else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_R) { view.lookAgain(); event.accepted = true }
          else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_S) { view.svc.showSetup(""); event.accepted = true }
        }

        Text {
          textFormat: Text.PlainText
          visible: search.text === ""
          anchors.verticalCenter: parent.verticalCenter
          text: view.bySite ? "Search nodes, sites and releases" : "Search nodes"
          color: Color.muted
          font: search.font
        }
      }
    }

    // ---- the nodes ---------------------------------------------------------------------------------
    Text {
      textFormat: Text.PlainText
      visible: view.rows.length > 0 && !view.bySite
      text: "NODES"
      color: Color.muted
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.letterSpacing: 1
    }

    RowLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.preferredHeight: list.contentHeight
      visible: view.rows.length > 0
      spacing: Style.spacing.md

      ListView {
        id: list
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: contentHeight
        clip: true
        spacing: Style.spacing.lg
        model: view.rows
        currentIndex: view.cursor
        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
        boundsBehavior: Flickable.StopAtBounds

        section.property: view.bySite ? "site" : ""
        section.delegate: Item {
          required property string section
          width: ListView.view.width
          height: sectionText.implicitHeight + Style.spacing.md
          Text {
            id: sectionText
            textFormat: Text.PlainText
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.spacing.xs
            text: (section === "" ? "NO SITE" : "SITE  ·  " + section.toUpperCase())
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
          }
        }

        delegate: NodeRow {
          required property var modelData
          required property int index
          width: ListView.view.width
          member: modelData
          stats: view.svc.nodeStats[modelData.host]
          target: view.progress ? view.progress.target : ""
          release: Model.clusterRelease(view.st)
          current: index === view.cursor
          busy: view.svc.busyHost === modelData.host
          onDetailsRequested: view.svc.showNode(modelData, "Status")
          onSettingsRequested: view.svc.showNode(modelData, "Settings")
          onRemoveRequested: view.svc.removeMember(modelData)
          onForceRequested: view.svc.forceUpgrade()
          onSelectRequested: { view.cursor = index; search.forceActiveFocus() }
        }
      }

      ScrollTrack {
        target: list
        Layout.fillHeight: true
        Layout.preferredWidth: implicitWidth
      }
    }

    // ---- nothing to list -----------------------------------------------------------------------------
    ColumnLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      visible: view.rows.length === 0
      Layout.preferredHeight: Style.space(130)
      spacing: Style.spacing.lg
      Item { Layout.fillHeight: true }
      Text {
        textFormat: Text.PlainText
        Layout.alignment: Qt.AlignHCenter
        text: !view.st.ok ? "The daemon is not answering" : view.query !== "" ? "No match for “" + view.query + "”" : "No members yet"
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.title
        font.bold: true
      }
      Text {
        textFormat: Text.PlainText
        Layout.alignment: Qt.AlignHCenter
        Layout.maximumWidth: parent.width - Style.space(40)
        visible: !view.st.ok
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: view.st.stopping || view.progress !== null
          ? "It is restarting, probably on a new release. This window looks again every few seconds."
          : "Start it with:  systemctl --user start startfs"
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
      Item { Layout.fillHeight: true }
    }

    // ---- invite: the command a new machine runs ----------------------------------------------------
    Rectangle {
      Layout.fillWidth: true
      visible: view.inviting
      implicitHeight: inviteCol.implicitHeight + Style.spacing.xxl * 2
      radius: Math.max(Style.cornerRadius, Style.space(6))
      color: Util.alpha(Color.foreground, 0.06)
      border.width: Style.normalBorderWidth
      border.color: Util.alpha(Color.foreground, 0.12)
      ColumnLayout {
        id: inviteCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.spacing.xxl
        anchors.rightMargin: Style.spacing.xxl
        spacing: Style.spacing.md
        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          wrapMode: Text.WordWrap
          text: view.svc.inviteError !== "" ? view.svc.inviteError
            : view.svc.inviteCommand === "" ? "Making an invitation..."
            : "On the new machine, with StartFS installed and its daemon running, run this within 24 hours."
            + (view.svc.inviteCopied ? " It is on your clipboard." : "")
          color: view.svc.inviteError !== "" ? Color.urgent : Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
        RowLayout {
          Layout.fillWidth: true
          visible: view.svc.inviteCommand !== ""
          spacing: Style.spacing.lg
          TextEdit {
            Layout.fillWidth: true
            readOnly: true
            selectByMouse: true
            wrapMode: TextEdit.WrapAnywhere
            text: view.svc.inviteCommand
            color: Color.foreground
            selectionColor: Util.alpha(Color.accent, 0.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
          Button {
            text: "Copy"
            bordered: true
            onClicked: view.svc.copyInvite()
          }
        }
      }
    }

    // ---- footer: invite on the left, the latest message or a hint on the right ------------------------
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.xxl

      Button {
        text: view.inviting ? "Done" : "+  Invite a node..."
        bordered: true
        visible: view.st.ok
        onClicked: {
          view.inviting = !view.inviting
          if (view.inviting) view.svc.makeInvite()
          search.forceActiveFocus()
        }
      }
      Text {
        textFormat: Text.PlainText
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
}

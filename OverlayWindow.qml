import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Config.js" as Config
import "KeyLabels.js" as Labels

PanelWindow {
  id: panel
  required property var outputScreen
  required property var config
  required property var strokes
  required property bool captureEnabled
  required property bool paused
  required property bool hiddenForApp
  required property string pauseText
  required property string focusedMonitorName
  readonly property real scale: Config.SIZE_SCALE[config.size]
  signal resumeRequested()
  screen: outputScreen

  readonly property string screenName: outputScreen ? outputScreen.name : ""
  readonly property bool allowed: panel.config.monitor === "all"
    || (panel.config.monitor === "focused" ? (focusedMonitorName === screenName) : panel.config.monitor === screenName)
  readonly property string position: panel.config.position
  readonly property bool atTop: position.indexOf("top") === 0
  readonly property bool atLeft: position.indexOf("left") > 0
  readonly property bool atRight: position.indexOf("right") > 0

  visible: allowed && (panel.paused || (panel.captureEnabled && !panel.hiddenForApp && strokes.length > 0))
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  WlrLayershell.namespace: "omarchy-keystrokes"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  exclusionMode: ExclusionMode.Ignore
  // Only the paused keycap accepts clicks; the rest stays click-through.
  mask: Region { item: panel.paused ? pauseCard : null }

  Column {
    id: stack
    // There are at most ten strokes. Build them all so the stack has a
    // real implicit height even when the overlay first becomes visible.
    width: Math.min(panel.width - Style.space(96), Style.space(900))
    height: implicitHeight
    // Position from the measured stack size. Switching opposing anchors
    // can leave a content-sized positioner stretched during a config update.
    x: panel.atLeft ? Style.space(48)
      : panel.atRight ? panel.width - width - Style.space(48)
      : Math.round((panel.width - width) / 2)
    y: panel.atTop ? Style.space(64) : panel.height - height - Style.space(64)
    spacing: Style.space(6)
    Item {
      id: pauseRow
      visible: panel.paused
      width: stack.width
      height: visible ? pauseCard.height : 0
      readonly property real pad: Style.space(8) * panel.scale
      BorderSurface {
        id: pauseCard
        x: panel.atRight ? pauseRow.width - width : panel.atLeft ? 0 : Math.round((pauseRow.width - width) / 2)
        width: Math.min(pauseRow.width, pauseLabel.implicitWidth + Style.space(14) * panel.scale
          + borderLeft + borderRight + pauseRow.pad * 2)
        height: borderTop + borderBottom + pauseRow.pad * 2 + pauseCap.height
        color: Util.alpha(Color.popups.background, 0.92)
        borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
        radius: Style.cornerRadius
        Rectangle {
          id: pauseCap
          anchors.centerIn: parent
          width: parent.width - parent.borderLeft - parent.borderRight - pauseRow.pad * 2
          height: Math.max(Math.round(Style.space(30) * panel.scale), pauseLabel.implicitHeight + Style.space(14) * panel.scale)
          radius: Math.min(Style.cornerRadius, Style.space(6))
          color: Util.alpha(Color.popups.text, resumeArea.containsMouse ? 0.22 : 0.16)
          border.width: 1
          border.color: Util.alpha(Color.popups.text, 0.45)
          Rectangle {
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            anchors.margins: 1
            height: Style.space(3)
            radius: parent.radius
            color: Util.alpha(Color.popups.text, 0.25)
          }
          Text {
            id: pauseLabel
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -1
            width: parent.width - Style.space(14) * panel.scale
            textFormat: Text.PlainText
            text: panel.pauseText
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Math.round(Style.font.title * panel.scale)
            font.bold: true
          }
        }
        MouseArea {
          id: resumeArea
          anchors.fill: parent
          enabled: panel.paused
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: panel.resumeRequested()
        }
      }
    }
    Repeater {
      model: panel.strokes
      delegate: Item {
        id: row
        required property var modelData
        readonly property int mods: modelData.mods
        readonly property int code: modelData.code
        readonly property int count: modelData.count
        readonly property var caps: Labels.caps(mods, code)
        readonly property real pad: Style.space(8) * panel.scale
        width: stack.width
        height: card.height


        BorderSurface {
          id: card
          // the card sits at the same edge the stack is anchored to
          x: panel.atRight ? row.width - width : panel.atLeft ? 0 : Math.round((row.width - width) / 2)
          width: card.borderLeft + row.pad + line.implicitWidth + row.pad + card.borderRight
          height: card.borderTop + row.pad + line.implicitHeight + row.pad + card.borderBottom
          color: Util.alpha(Color.popups.background, 0.92)
          borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
          radius: Style.cornerRadius

          Row {
            id: line
            anchors.centerIn: parent
            spacing: Style.space(6) * panel.scale

            Repeater {
              model: row.caps
              Item {
                required property string modelData
                required property int index
                readonly property bool isMod: index < row.caps.length - 1 || Labels.isModifier(row.code)
                width: cap.width + (index < row.caps.length - 1 ? plus.width + line.spacing : 0)
                height: cap.height

                // a keycap: a raised face with a heavier bottom edge
                Rectangle {
                  id: cap
                  width: Math.max(height, capText.implicitWidth + Style.space(14) * panel.scale)
                  height: Math.round(Style.space(30) * panel.scale)
                  radius: Math.min(Style.cornerRadius, Style.space(6))
                  color: Util.alpha(Color.popups.text, isMod ? 0.10 : 0.16)
                  border.width: 1
                  border.color: Util.alpha(Color.popups.text, 0.45)
                  Rectangle {
                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                    anchors.margins: 1
                    height: Style.space(3)
                    radius: parent.radius
                    color: Util.alpha(Color.popups.text, 0.25)
                  }
                  Text {
                    id: capText
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -1
                    textFormat: Text.PlainText
                    text: modelData
                    color: Color.popups.text
                    font.family: Style.font.family
                    font.pixelSize: Math.round(Style.font.title * panel.scale)
                    font.bold: true
                  }
                }
                Text {
                  id: plus
                  visible: index < row.caps.length - 1
                  anchors.left: cap.right
                  anchors.leftMargin: line.spacing
                  anchors.verticalCenter: cap.verticalCenter
                  textFormat: Text.PlainText
                  text: "+"
                  color: Util.alpha(Color.popups.text, 0.6)
                  font.family: Style.font.family
                  font.pixelSize: Math.round(Style.font.body * panel.scale)
                }
              }
            }

            Text {
              visible: row.count > 1
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "×" + row.count
              color: Util.alpha(Color.popups.text, 0.75)
              font.family: Style.font.family
              font.pixelSize: Math.round(Style.font.body * panel.scale)
              font.bold: true
            }
          }
        }
      }
    }
  }
}

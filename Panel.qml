import QtQuick
import "."
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import qs.Ui as Ui
import "Config.js" as Config

// Settings for the keystroke overlay: a bar button (the icon lights up while
// the overlay is on) and its popup. Everything is a write to
// ~/.config/omarchy/keystrokes.json, which the overlay watches; on/off goes
// over the overlay's IPC.
Ui.Panel {
  id: root
  moduleName: "markpriem.keystrokes"
  ipcTarget: "markpriem.keystrokes-panel"

  readonly property string home: Quickshell.env("HOME")
  readonly property string configPath: home + "/.config/omarchy/keystrokes.json"

  readonly property var rawConfig: configFile.raw
  readonly property var config: configFile.values
  readonly property string configError: configFile.error

  property bool enabled: false
  property bool requested: false
  property string pauseReason: ""
  property bool statusAvailable: false
  property bool statusTimedOut: false
  property int actionRevision: 0
  property string captureError: ""
  property string shortcut: ""
  readonly property var screens: Quickshell.screens
  readonly property color fg: root.barForeground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(fg, 1.4)
  property int editMs: -1
  readonly property int shownMs: editMs >= 0 ? editMs : config.timeoutMs

  readonly property var monitorOptions: Config.MONITOR_OPTIONS.concat(screens.map(function(s) { return { value: s.name, label: s.name } }))

  // the overlay re-reads the file on request: a watch set before the file
  // existed would never see it appear
  function save(next) { configFile.save(next) }
  function set(key, value) { save(Config.withValue(rawConfig, key, value)) }
  function setEnabled(on) { requested = !!on; actionRevision++; Util.execArgv(["omarchy-shell", "markpriem.keystrokes", on ? "on" : "off"]); statePoll.restart() }
  function toggleEnabled() { setEnabled(!requested) }
  function hideForText() { return config.hideFor.join(", ") }
  function setHideFor(text) {
    set("hideFor", String(text || "").split(",").map(function(s) { return s.trim() }).filter(function(s) { return s.length > 0 }))
  }

  // ---- keyboard cursor (the kit's recipe; Tab sections, arrows options, Enter) ----
  property bool cursorActive: false
  property string focusSection: ""
  property int selectedIndex: 0
  readonly property var sections: [
    { id: "power", n: 1, cols: 1 }, { id: "position", n: Config.POSITIONS.length, cols: 3 },
    { id: "monitor", n: monitorOptions.length, cols: Math.min(3, monitorOptions.length) }, { id: "size", n: Config.SIZE_OPTIONS.length, cols: 3 },
    { id: "order", n: Config.ORDER_OPTIONS.length, cols: 2 }, { id: "timeout", n: 1, cols: 1 }, { id: "combos", n: 1, cols: 1 },
    { id: "sudo", n: 1, cols: 1 }, { id: "mods", n: 1, cols: 1 }, { id: "repeats", n: 1, cols: 1 }, { id: "autooff", n: Config.AUTO_OFF_OPTIONS.length, cols: 4 },
    { id: "hidefor", n: 1, cols: 1 }
  ]
  function section(id) { for (var i = 0; i < sections.length; i++) if (sections[i].id === id) return sections[i]; return null }
  function setCursor(id, index) {
    var sec = section(id)
    cursorActive = true
    focusSection = id
    selectedIndex = Math.max(0, Math.min(index, sec ? sec.n - 1 : 0))
  }
  function homeIndex(id) {
    var lists = { position: Config.POSITIONS, monitor: monitorOptions, size: Config.SIZE_OPTIONS, order: Config.ORDER_OPTIONS, autooff: Config.AUTO_OFF_OPTIONS }
    var values = { position: config.position, monitor: config.monitor, size: config.size, order: config.order, autooff: String(config.autoOffMinutes) }
    if (!lists[id]) return 0
    for (var i = 0; i < lists[id].length; i++) if (lists[id][i].value === values[id]) return i
    return 0
  }
  function moveSection(direction) {
    var at = -1
    for (var i = 0; i < sections.length; i++) if (sections[i].id === focusSection) at = i
    var next = at < 0 ? (direction > 0 ? 0 : sections.length - 1) : (at + direction + sections.length) % sections.length
    setCursor(sections[next].id, homeIndex(sections[next].id))
    if (sections[next].id === "hidefor") hideField.forceActiveFocus()
  }
  function moveCursor(dx, dy) {
    if (!cursorActive || !section(focusSection)) { moveSection(1); return }
    var sec = section(focusSection)
    if (sec.id === "timeout") { if (dx) set("timeoutMs", Math.max(Config.TIMEOUT_MIN_MS, Math.min(Config.TIMEOUT_MAX_MS, config.timeoutMs + dx * 250))); else if (dy) moveSection(dy); return }
    if (sec.n === 1) { if (dy) moveSection(dy); return }
    var next = selectedIndex + dx + dy * sec.cols
    if (dx && (next < 0 || next >= sec.n)) return
    if (dy && (next < 0 || next >= sec.n)) { moveSection(dy); return }
    selectedIndex = next
  }
  onMonitorOptionsChanged: if (focusSection === "monitor") selectedIndex = Math.max(0, Math.min(selectedIndex, monitorOptions.length - 1))
  function activateCursor() {
    if (!cursorActive) { moveSection(1); return }
    var sec = section(focusSection)
    var i = Math.max(0, Math.min(selectedIndex, sec ? sec.n - 1 : 0))
    switch (focusSection) {
    case "power": toggleEnabled(); break
    case "position": set("position", Config.POSITIONS[i].value); break
    case "monitor": set("monitor", monitorOptions[i].value); break
    case "size": set("size", Config.SIZE_OPTIONS[i].value); break
    case "order": set("order", Config.ORDER_OPTIONS[i].value); break
    case "combos": set("combosOnly", !config.combosOnly); break
    case "sudo": set("sudoProtection", !config.sudoProtection); break
    case "mods": set("modifiersAlone", !config.modifiersAlone); break
    case "repeats": set("collapseRepeats", !config.collapseRepeats); break
    case "autooff": set("autoOffMinutes", Number(Config.AUTO_OFF_OPTIONS[i].value)); break
    case "hidefor": hideField.forceActiveFocus(); hideField.selectAll(); break
    }
  }
  onOpenedChanged: if (opened) { cursorActive = false; focusSection = ""; hideField.text = hideForText(); statePoll.restart() }


  // ---- inputs ----
  SettingsFile {
    id: configFile
    path: root.configPath
    onSaved: { Util.execArgv(["omarchy-shell", "markpriem.keystrokes", "refresh"]); statePoll.restart() }
  }
  function applyState(state) {
    if (!state || typeof state.enabled !== "boolean" || typeof state.requested !== "boolean") { unavailable(); return }
    statusAvailable = true
    requested = state.requested
    pauseReason = String(state.pauseReason || "")
    enabled = state.enabled
    captureError = String(state.error || "")
    shortcut = String(state.shortcut || "")
  }
  Connections {
    target: CaptureStatus
    function onStateChanged() {
      if (CaptureStatus.state) {
        statusDeadline.stop()
        if (statusProcess.running) statusProcess.signal(9)
        root.applyState(CaptureStatus.state)
      } else statePoll.restart()
    }
  }
  function pollState() {
    if (CaptureStatus.state) { applyState(CaptureStatus.state); return }
    if (statusProcess.running) return
    statusTimedOut = false
    statusProcess.revision = actionRevision
    statusDeadline.restart()
    statusProcess.running = true
  }
  function unavailable() { statusAvailable = false; captureError = "Capture status unavailable." }
  Process {
    id: statusProcess
    property int revision: 0
    command: ["omarchy-shell", "markpriem.keystrokes", "state"]
    stdout: StdioCollector { id: statusOutput; waitForEnd: true }
    stderr: StdioCollector {}
    onExited: function(exitCode) {
      statusDeadline.stop()
      if (CaptureStatus.state) { root.applyState(CaptureStatus.state); return }
      if (revision !== root.actionRevision) { statePoll.restart(); return }
      if (exitCode !== 0 || root.statusTimedOut) { root.unavailable(); return }
      try {
        root.applyState(JSON.parse(statusOutput.text))
      } catch (e) { root.unavailable() }
    }
  }
  Timer {
    id: statusDeadline; interval: 2000
    onTriggered: { root.statusTimedOut = true; root.unavailable(); statusProcess.signal(9) }
  }
  Timer { id: statePoll; interval: 250; repeat: false; onTriggered: root.pollState() }
  Timer { interval: 1000; repeat: true; running: !CaptureStatus.state && (root.opened || root.bar !== null); onTriggered: root.pollState() }
  Component.onCompleted: statePoll.start()

  component ChipRow: Grid {
    id: chips
    property var options: []
    property string value: ""
    property string section: ""
    signal changed(string value)
    columns: options.length
    columnSpacing: Style.space(6)
    rowSpacing: Style.space(6)
    Repeater {
      model: chips.options
      Button {
        required property var modelData
        required property int index
        width: (chips.width - chips.columnSpacing * (chips.columns - 1)) / Math.max(1, chips.columns)
        text: modelData.label
        selected: modelData.value === chips.value
        hasCursor: root.cursorActive && root.focusSection === chips.section && root.selectedIndex === index
        bordered: true
        foreground: root.fg
        fontFamily: root.fontFamily
        onClicked: chips.changed(modelData.value)
        onHovered: function(h) { if (h) root.setCursor(chips.section, index) }
      }
    }
  }

  // ---- bar button + popup ----
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰌌"
    active: root.enabled
    tooltipText: root.enabled ? "Keystrokes: on" : "Keystrokes"
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: hideField.activeFocus
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.cursorActive = true; root.moveSection(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        PanelHero {
          title: "Keystrokes"
          meta: root.enabled ? "Showing what you press" : "Off"
          detail: root.shortcut || "No toggle shortcut"
          foreground: root.fg
          fontFamily: root.fontFamily
          iconComponent: Component {
            Text { textFormat: Text.PlainText; text: "󰌌"; color: root.fg; font.family: root.fontFamily; font.pixelSize: Style.font.display }
          }
        }

        PanelSeparator { foreground: root.fg }

        Toggle {
          width: parent.width
          label: "Show keystrokes"
          description: "Keys you press appear as keycaps on screen"
          checked: root.enabled
          foreground: root.fg
          fontFamily: root.fontFamily
          hasCursor: root.cursorActive && root.focusSection === "power"
          onClicked: root.toggleEnabled()
          onHovered: function(h) { if (h) root.setCursor("power", 0) }
        }

        Column {
          width: parent.width
          spacing: Style.space(10)
          PanelSectionHeader { text: "PLACEMENT"; foreground: root.fg; fontFamily: root.fontFamily }
          ChipRow { width: parent.width; columns: 3; section: "position"; options: Config.POSITIONS; value: root.config.position; onChanged: function(v) { root.set("position", v) } }
          ChipRow { width: parent.width; columns: Math.min(3, root.monitorOptions.length); section: "monitor"; options: root.monitorOptions; value: root.config.monitor; onChanged: function(v) { root.set("monitor", v) } }
          ChipRow { width: parent.width; section: "size"; options: Config.SIZE_OPTIONS; value: root.config.size; onChanged: function(v) { root.set("size", v) } }
          ChipRow { width: parent.width; section: "order"; options: Config.ORDER_OPTIONS; value: root.config.order; onChanged: function(v) { root.set("order", v) } }
        }

        Column {
          width: parent.width
          spacing: Style.space(10)
          PanelSectionHeader { text: "BEHAVIOUR"; foreground: root.fg; fontFamily: root.fontFamily }

          CursorSurface {
            width: parent.width
            implicitHeight: timeoutRow.implicitHeight + Style.space(8)
            outline: true
            foreground: root.fg
            hasCursor: root.cursorActive && root.focusSection === "timeout"
            HoverHandler { onHoveredChanged: if (hovered) root.setCursor("timeout", 0) }
            Row {
              id: timeoutRow
              anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(6); anchors.rightMargin: Style.space(6)
              spacing: Style.space(10)
              Text { anchors.verticalCenter: parent.verticalCenter; textFormat: Text.PlainText; text: "Stays for"; color: root.fg; font.family: root.fontFamily; font.pixelSize: Style.font.body }
              PanelSlider {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - timeoutLabel.width - stayLabel.width - parent.spacing * 2
                bar: root.bar
                minimum: Config.TIMEOUT_MIN_MS; maximum: Config.TIMEOUT_MAX_MS; step: 250; integer: true
                value: root.config.timeoutMs
                onMoved: function(v) { root.editMs = v }
                onReleased: function(v) { root.editMs = -1; root.set("timeoutMs", v) }
              }
              Text { id: timeoutLabel; anchors.verticalCenter: parent.verticalCenter; width: Style.space(44); textFormat: Text.PlainText; text: Config.timeoutLabel(root.shownMs); color: root.fg; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
            }
            Text { id: stayLabel; visible: false; text: "Stays for"; font.family: root.fontFamily; font.pixelSize: Style.font.body }
          }

          Toggle {
            width: parent.width; label: "Shortcuts only"; description: "Capture only strokes with Ctrl, Alt or Super"
            checked: root.config.combosOnly; foreground: root.fg; fontFamily: root.fontFamily
            hasCursor: root.cursorActive && root.focusSection === "combos"
            onClicked: root.set("combosOnly", !root.config.combosOnly); onHovered: function(h) { if (h) root.setCursor("combos", 0) }
          }
          Toggle {
            width: parent.width; label: "SUDO protection"; description: "Pause capture after typing sudo followed by Space"
            checked: root.config.sudoProtection; foreground: root.fg; fontFamily: root.fontFamily
            hasCursor: root.cursorActive && root.focusSection === "sudo"
            onClicked: root.set("sudoProtection", !root.config.sudoProtection); onHovered: function(h) { if (h) root.setCursor("sudo", 0) }
          }
          Toggle {
            width: parent.width; label: "Modifiers on their own"; description: "Show a tap of Super, Ctrl, Alt or Shift by itself"
            checked: root.config.modifiersAlone; foreground: root.fg; fontFamily: root.fontFamily
            hasCursor: root.cursorActive && root.focusSection === "mods"
            onClicked: root.set("modifiersAlone", !root.config.modifiersAlone); onHovered: function(h) { if (h) root.setCursor("mods", 0) }
          }
          Toggle {
            width: parent.width; label: "Collapse repeats"; description: "The same stroke again becomes ×2, ×3, …"
            checked: root.config.collapseRepeats; foreground: root.fg; fontFamily: root.fontFamily
            hasCursor: root.cursorActive && root.focusSection === "repeats"
            onClicked: root.set("collapseRepeats", !root.config.collapseRepeats); onHovered: function(h) { if (h) root.setCursor("repeats", 0) }
          }

          Text { textFormat: Text.PlainText; text: "Turn off by itself after"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
          ChipRow { width: parent.width; section: "autooff"; options: Config.AUTO_OFF_OPTIONS; value: String(root.config.autoOffMinutes); onChanged: function(v) { root.set("autoOffMinutes", Number(v)) } }

          Text { textFormat: Text.PlainText; text: "Hide in these apps (window classes, comma separated)"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
          TextField {
            id: hideField
            width: parent.width
            placeholderText: "1password, bitwarden, hyprlock"
            foreground: root.fg
            font.family: root.fontFamily
            hasCursor: !activeFocus && root.cursorActive && root.focusSection === "hidefor"
            onHoveredChanged: if (hovered) root.setCursor("hidefor", 0)
            onEditingFinished: root.setHideFor(text)
            Keys.onPressed: function(e) {
              if (e.key === Qt.Key_Escape || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { root.setHideFor(text); keyCatcher.forceActiveFocus(); e.accepted = true }
              else if (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab || e.key === Qt.Key_Up || e.key === Qt.Key_Down) { root.setHideFor(text); keyCatcher.forceActiveFocus(); root.moveSection(e.key === Qt.Key_Backtab || e.key === Qt.Key_Up ? -1 : 1); e.accepted = true }
            }
          }
        }

        PanelSeparator { foreground: root.fg }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          wrapMode: Text.WordWrap
          text: ((root.configError || root.captureError) ? (root.configError || root.captureError) + "\n" : "")
            + "Turn capture off before entering secrets. Full typing can display passwords in allowed apps. Key names use a US layout."
            + "\nTab ⇧Tab section · ←↑↓→ hjkl option · Enter confirm"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}

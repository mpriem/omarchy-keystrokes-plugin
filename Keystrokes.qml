import QtQuick
import "."
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "KeyLabels.js" as Labels
import "CaptureProtocol.js" as Protocol

// Filtered key events arrive through private tmpfs snapshots. Capture and
// the overlay always start off; appearance preferences are the only saved state.
Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string configPath: home + "/.config/omarchy/keystrokes.json"

  readonly property var config: configFile.values
  readonly property string configError: configFile.error

  readonly property bool enabled: capture.enabled
  readonly property bool paused: capture.pauseReason !== ""
  // The shell must see startup and the visible pause prompt as open too.
  readonly property bool opened: capture.requested || paused
  readonly property string pauseText: Labels.pauseText(capture.pauseReason, capture.shortcut)
  StrokeModel { id: history; config: root.config }

  readonly property var captureState: ({ enabled: enabled, requested: capture.requested,
    pauseReason: capture.pauseReason, shortcut: capture.shortcut, error: configError || capture.error })
  Component.onCompleted: CaptureStatus.source = root
  Component.onDestruction: if (CaptureStatus.source === root) CaptureStatus.source = null

  // ---- on / off ----
  Capture {
    id: capture
    config: root.config
    onStroke: function(event) { root.ingest(event) }
    onCleared: history.clear()
  }
  function setEnabled(on) { if (on && (!configFile.loaded || configError)) { capture.fail(configError || "Settings are still loading."); return }; capture.setEnabled(on); history.clear() }
  function open(payloadJson) { setEnabled(true) }
  function close() { setEnabled(false) }
  function toggle() { setEnabled(!capture.requested) }
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "configreloaded") { root.setEnabled(false); capture.refreshBinding() }
    }
  }

  // ---- what to show ----
  readonly property string activeClass: ToplevelManager.activeToplevel ? String(ToplevelManager.activeToplevel.appId || "") : ""
  readonly property bool hiddenForApp: {
    var cls = activeClass.toLowerCase()
    if (!cls) return true
    for (var i = 0; i < config.hideFor.length; i++) {
      var h = String(config.hideFor[i] || "").toLowerCase().trim()
      if (h && cls.indexOf(h) >= 0) return true
    }
    return false
  }

  onActiveClassChanged: history.clear()
  onHiddenForAppChanged: if (hiddenForApp) history.clear()

  function ingest(event) {
    if (enabled && !hiddenForApp && event) history.ingest(event)
  }

  // ---- inputs ----
  SettingsFile {
    id: configFile
    path: root.configPath
    onInvalid: capture.fail(error)
  }

  IpcHandler {
    target: "markpriem.keystrokes"
    function on(): string { root.setEnabled(true); return "starting" }
    function off(): string { root.setEnabled(false); return "off" }
    function toggle(): string { root.toggle(); return capture.requested ? "starting" : "off" }
    function status(): string { return root.enabled ? "on" : "off" }
    function refresh(): void { configFile.reload() }
    function clear(): void { history.clear() }
    // push <keycode> [mods]: show a stroke without pressing it (tests)
    function push(code: string, mods: string): void { root.ingest(Protocol.event(Number(code), Number(mods || "0"))) }
    function state(): string {
      return JSON.stringify(root.captureState)
    }
  }

  // ---- the overlay, per monitor ----
  Variants {
    model: Quickshell.screens

    OverlayWindow {
      required property var modelData
      outputScreen: modelData
      config: root.config
      strokes: history.rows
      captureEnabled: root.enabled
      paused: root.paused
      hiddenForApp: root.hiddenForApp
      pauseText: root.pauseText
      focusedMonitorName: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
      onResumeRequested: root.setEnabled(true)
    }
  }
}

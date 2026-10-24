import QtQuick
import Quickshell
import "." as Plugin
import qs.Ui as Ui
import qs.Commons as Commons
ShellRoot {
  id: root
  Plugin.Keystrokes { id: overlay }
  readonly property string mode: Quickshell.env("TEST_MODE")
  property QtObject fixture: QtObject { property var captureState: ({enabled:false,requested:false,pauseReason:"",error:"",shortcut:""}) }
  Ui.PluginBarApi { id: barApi; pluginId: "markpriem.keystrokes"; moduleName: "markpriem.keystrokes" }
  Plugin.Panel { id: panel; bar: barApi; manageIpc: false }
  Plugin.Panel { id: second; bar: barApi; manageIpc: false }
  Plugin.Panel { id: third; bar: barApi; manageIpc: false }
  Plugin.StrokeModel { id: history; config: overlay.config }
  Plugin.OverlayWindow {
    id: view
    outputScreen: Quickshell.screens[0]
    config: overlay.config
    strokes: history.rows
    captureEnabled: true
    paused: false
    hiddenForApp: false
    pauseText: "SUDO Found - Click or Super+Shift+K to continue"
    focusedMonitorName: outputScreen.name
  }
  Timer {
    interval: 200; running: true
    onTriggered: {
      if (overlay.configPath.indexOf('/keystrokes.json') < 0) throw new Error("settings path changed")
      history.ingest({code:38,mods:1})
      history.ingest({code:38,mods:1})
      if (history.count !== 1 || history.rows[0].count !== 2) throw new Error("history presentation failed")
      panel.setCursor("monitor", 999)
      if (panel.selectedIndex !== panel.monitorOptions.length - 1) throw new Error("monitor navigation out of range")
      panel.setCursor("monitor", 0)
      panel.moveCursor(1,0)
      panel.moveSection(1)
      if (root.mode.indexOf("fallback") === 0) Plugin.CaptureStatus.source = null
      else {
        Plugin.CaptureStatus.source = root.fixture
        root.fixture.captureState = {enabled:false,requested:true,pauseReason:"",error:"",shortcut:"Super+Shift+K"}
        if (!panel.requested || panel.enabled || !second.requested || !third.requested) throw new Error("starting state not shared")
        root.fixture.captureState = {enabled:false,requested:false,pauseReason:"sudo",error:"",shortcut:"Super+Shift+K"}
        if (panel.requested || panel.pauseReason !== "sudo") throw new Error("pause state not shared")
        root.fixture.captureState = {enabled:true,requested:true,pauseReason:"",error:"",shortcut:"Super+Shift+K"}
        if (!panel.enabled || !third.enabled) throw new Error("active state not shared")
      }
    }
  }
  function findText(item, text) {
    if (item.text === text) return item
    var children = item.children || []
    for (var i = 0; i < children.length; i++) {
      var found = findText(children[i], text)
      if (found) return found
    }
    return null
  }
  Timer {
    interval: 400; running: true
    onTriggered: {
      // Exercise instantiated keycaps, not only component loading. Qt 6.12
      // exports QtQuick.Color, which must not replace the Omarchy palette.
      var cap = root.findText(view.contentItem, "Ctrl")
      if (!cap || !Qt.colorEqual(cap.color, Commons.Color.popups.text)) throw new Error("keycap theme color missing")
      history.clear()
      if (history.count !== 0) throw new Error("privacy clear failed")
    }
  }
  Timer {
    interval: 3300; running: true
    onTriggered: {
      if (root.mode === "fallback-fail" || root.mode === "fallback-timeout") {
        if (panel.statusAvailable || !panel.captureError) throw new Error("unavailable status hidden")
      } else if (!panel.statusAvailable) throw new Error("status missing")
      console.log("PASS: QML full overlay, panel and extracted view load " + root.mode)
      Qt.quit()
    }
  }
}

import QtQuick
import Quickshell
import "."

ShellRoot {
  property int count: 0
  property bool turnedOff: false
  property bool resumed: false
  property double pausedAt: 0
  readonly property string mode: Quickshell.env("TEST_MODE")
  readonly property bool pauseTest: ["sudo", "polkit", "custom", "unbound"].indexOf(mode) >= 0
  readonly property bool stalled: Quickshell.env("TEST_MODE") === "stalled"
  readonly property string expectedShortcut: mode === "custom" ? "Super+Shift+J" : mode === "unbound" ? "" : "Super+Shift+K"
  Capture {
    id: capture
    config: ({sudoProtection: true, combosOnly: true, modifiersAlone: false, hideFor: [], autoOffMinutes: 0})
    onReadyChanged: if (ready) {
      if (shortcut !== expectedShortcut) throw new Error("wrong startup shortcut")
      if (mode === "reload") refreshBinding()
      else setEnabled(true)
    }
    onStroke: function(line) {
      if (line.code !== 38 || line.mods !== 1 || !enabled) throw new Error("invalid fixture stroke")
      count++
      if (!stalled && count === 30) { turnedOff = true; setEnabled(false) }
    }
  }
  Timer {
    interval: 20; running: true; repeat: true
    onTriggered: {
      if (mode === "reload") {
        if (capture.ready && !capture.busy && !capture.bindingRefreshNeeded) {
          if (capture.shortcut !== "Alt+F10" || capture.requested || capture.enabled) throw new Error("off-state refresh failed")
          console.log("PASS: QML shortcut refresh while capture is off")
          Qt.quit()
        }
        return
      }
      if (pauseTest && !resumed && capture.pauseReason && !capture.directory && !capture.busy) {
        if (capture.enabled || capture.requested || capture.pauseReason !== (mode === "polkit" ? "polkit" : "sudo") || capture.shortcut !== expectedShortcut || count !== 1)
          throw new Error("invalid paused state")
        if (!pausedAt) pausedAt = Date.now()
        if (Date.now() - pausedAt >= 350) { resumed = true; capture.setEnabled(true) }
      }
      if ((turnedOff || (stalled && count === 3 && capture.error)) && !capture.requested && !capture.directory && !capture.busy) {
        if (pauseTest && (!resumed || capture.pauseReason)) throw new Error("resume failed")
        console.log("PASS: QML " + (pauseTest ? mode + " pause, cleanup and explicit resume" : stalled ? "stale producer stops capture" : "30 rotations, ACKs and shutdown"))
        Qt.quit()
      }
    }
  }
  Timer { interval: 6000; running: true; onTriggered: { console.error("FAIL: QML timeout", capture.error, count, capture.directory); Qt.quit() } }
}

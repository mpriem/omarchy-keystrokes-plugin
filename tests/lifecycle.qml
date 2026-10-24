import QtQuick
import Quickshell
import Quickshell.Io
import "."
ShellRoot {
  id: root
  readonly property string mode: Quickshell.env("TEST_MODE")
  property bool acted: false
  property int strokes: 0
  property bool destroyed: false
  property var oldOperation: null
  Loader {
    id: loader
    active: true
    sourceComponent: Component {
      Capture {
        id: capture
        config: ({sudoProtection: true, combosOnly: true, modifiersAlone: false, hideFor: [], autoOffMinutes: 0})
        onReadyChanged: if (ready) {
          if (root.mode === "spawn-retry") run("binding", ["/nonexistent-keystrokes-test-command"])
          else setEnabled(true)
        }
        onPhaseChanged: Qt.callLater(function() {
          if (root.acted) return
          if (root.mode === "destroy-create" && phase === "creating") {
            root.acted = true; root.destroyed = true; loader.active = false; return
          }
          if (root.mode === "cancel-create" && phase === "creating") { root.acted = true; setEnabled(false) }
          if (["cancel-start", "restart", "config-start", "late"].indexOf(root.mode) >= 0 && phase === "starting") {
            root.acted = true
            root.oldOperation = operation
            if (root.mode === "config-start") config = {sudoProtection:true,combosOnly:true,modifiersAlone:false,hideFor:["private-editor"],autoOffMinutes:15}
            else { setEnabled(false); if (root.mode !== "cancel-start") setEnabled(true) }
          }
        })
        onStroke: function(line) {
          root.strokes++
          if (root.mode === "destroy") { root.destroyed = true; loader.active = false; return }
          if (root.mode === "batch") {
            setEnabled(false)
            return
          }
          if (root.oldOperation && root.mode === "late") {
            var owned = token
            finished(root.oldOperation.id, 0, "keystrokes-v5 waiting")
            if (token !== owned || !enabled) throw new Error("stale completion changed current session")
          }
          setEnabled(false)
        }
      }
    }
  }
  Process {
    id: repair
    onExited: function(code) {
      if (code !== 0) throw new Error("cleanup repair failed")
      loader.item.setEnabled(false)
    }
  }
  Timer {
    interval: 20; running: true; repeat: true
    onTriggered: {
      if (root.destroyed) { console.log("PASS: QML destruction launches ordered cleanup"); Qt.quit(); return }
      var c = loader.item
      if (root.mode === "spawn-retry" && !root.acted && c && c.ready && !c.busy) {
        root.acted = true
        c.setEnabled(true)
        return
      }
      if (c && c.cleanupBlocked && root.mode === "cleanup-fail" && !root.acted) {
        if (c.enabled || c.requested || !c.directory || !c.token || c.cleanupAttempts !== 3) throw new Error("cleanup ownership lost")
        root.acted = true
        repair.command = ["rm", "--", c.directory + "/extra"]
        repair.running = true
      }
      if (!c || !c.ready || c.busy || c.directory || c.requested) return
      if (root.mode === "ack-fail" && (!c.error || root.strokes !== 0)) throw new Error("ACK failure did not stop capture")
      if (root.mode === "spawn-fail" && (!c.error || root.strokes !== 0)) throw new Error("spawn failure did not settle safely")
      if (root.mode === "spawn-retry" && (!root.acted || root.strokes === 0 || c.error)) throw new Error("capture did not recover after a failed launch")
      if (root.mode === "start-timeout" && !c.error) throw new Error("timeout lost")
      if (["stop-fail", "stop-timeout"].indexOf(root.mode) >= 0 && (!c.error || c.stopAcknowledged)) throw new Error("stop failure lost")
      if (["cancel-create", "cancel-start", "start-timeout"].indexOf(root.mode) >= 0 && root.strokes !== 0) throw new Error("cancelled startup delivered input")
      if (root.mode === "batch" && root.strokes !== 1) throw new Error("off signal did not interrupt delivery")
      console.log("PASS: QML lifecycle " + root.mode)
      Qt.quit()
    }
  }
  Timer { interval: 8000; running: true; onTriggered: { console.error("FAIL: lifecycle timeout"); Qt.quit() } }
}

import QtQuick
import Quickshell
import "." as Plugin

ShellRoot {
  id: root
  Plugin.Keystrokes { id: overlay }
  property int stage: 0

  // Exercise the open/close/opened interface used by shell summon/hide/toggle.
  function toggleFromHost() { overlay.opened ? overlay.close() : overlay.open("{}") }
  Timer {
    interval: 200; running: true
    onTriggered: {
      if (overlay.opened) throw new Error("entry started open")
      overlay.open("{}")
      overlay.open("{}")
      if (!overlay.opened || !overlay.captureState.requested) throw new Error("summon did not request capture")
      root.stage = 1
    }
  }
  Timer {
    interval: 10; running: true; repeat: true
    onTriggered: {
      if (root.stage === 1 && overlay.paused) {
        if (!overlay.opened || overlay.captureState.requested) throw new Error("pause prompt has wrong open state")
        root.toggleFromHost()
        if (overlay.opened || overlay.paused || overlay.enabled) throw new Error("hide did not dismiss pause")
        root.toggleFromHost()
        if (!overlay.opened || !overlay.captureState.requested) throw new Error("toggle did not reopen capture")
        root.stage = 2
      } else if (root.stage === 2 && overlay.enabled) {
        overlay.close()
        overlay.close()
        if (overlay.opened || overlay.enabled || overlay.captureState.requested) throw new Error("hide did not stop capture")
        root.stage = 3
        finish.start()
      }
    }
  }
  Timer {
    id: finish; interval: 500
    onTriggered: {
      if (overlay.opened || overlay.enabled || overlay.captureState.error) throw new Error("entry failed to stay closed")
      console.log("PASS: QML full entry lifecycle: summon, pause, toggle, reopen and hide")
      Qt.quit()
    }
  }
  Timer { interval: 6000; running: true; onTriggered: { console.error("FAIL: entry lifecycle timeout", root.stage, overlay.captureState.error); Qt.quit() } }
}

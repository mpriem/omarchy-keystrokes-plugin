import QtQuick
import Quickshell
import Quickshell.Io
import "."
ShellRoot {
  id: root
  property int step: 0
  property int saves: 0
  readonly property string folder: Quickshell.env("XDG_RUNTIME_DIR")
  SettingsFile {
    id: settings
    path: root.folder + "/settings.json"
    onSaved: root.saves++
    onInvalid: capture.fail(error)
  }
  Capture { id: capture; config: settings.values }
  FileView {
    id: external
    path: root.folder + "/settings.json"
    printErrors: false
    onSaved: settings.reload()
  }
  Timer {
    interval: 20; running: true; repeat: true
    onTriggered: {
      if (root.step === 0 && settings.loaded) {
        settings.save({hideFor:["private-editor"],autoOffMinutes:15})
        settings.save({hideFor:["private-editor"],autoOffMinutes:60})
        root.step = 1
      } else if (root.step === 1 && root.saves && !settings.dirty && capture.ready) {
        if (root.saves !== 1 || settings.values.autoOffMinutes !== 60) throw new Error("edits not coalesced")
        capture.setEnabled(true)
        root.step = 10
      } else if (root.step === 10 && capture.enabled) {
        external.setText("{")
        root.step = 2
      } else if (root.step === 2 && settings.error) {
        if (capture.requested || capture.enabled) throw new Error("invalid policy still capturing")
        if (settings.values.hideFor[0] !== "private-editor" || settings.values.autoOffMinutes !== 60) throw new Error("privacy policy lost")
        settings.save({hideFor:[],autoOffMinutes:15})
        root.step = 3
      } else if (root.step === 3 && !settings.dirty && !settings.error) {
        settings.path = root.folder
        settings.save({hideFor:["pending"],autoOffMinutes:15})
        root.step = 4
      } else if (root.step === 4 && !settings.saving && settings.error) {
        if (!settings.dirty || settings.values.hideFor[0] !== "pending") throw new Error("failed save lost edits")
        settings.path = root.folder + "/settings.json"
        settings.retry()
        root.step = 5
      } else if (root.step === 5 && !settings.dirty && !settings.error && !capture.directory && !capture.busy) {
        if (capture.requested || capture.enabled) throw new Error("policy repair auto-resumed capture")
        console.log("PASS: QML settings first use, coalescing, invalid reload, failed save and retry")
        Qt.quit()
      }
    }
  }
  Timer { interval: 6000; running: true; onTriggered: { console.error("FAIL: settings timeout", root.step, settings.error); Qt.quit() } }
}

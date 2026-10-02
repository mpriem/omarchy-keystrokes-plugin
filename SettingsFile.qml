import QtQuick
import Quickshell.Io
import "Config.js" as Config

// Last valid document and local edits belong here, independently of capture.
// While dirty, local edits win over watcher echoes/external edits. After a
// successful write the file is authoritative again. Failed edits stay dirty.
Item {
  id: root
  required property string path
  property var raw: ({})
  readonly property var values: Config.read(raw)
  property bool loaded: false
  property bool dirty: false
  property bool saving: false
  property string error: ""
  property int revision: 0
  property int writingRevision: 0
  property string writingText: ""
  signal invalid()
  signal saved()
  function rejectLoad() {
    error = "Settings could not be loaded. Capture is off; fix settings and turn it on again."
    invalid()
  }
  function reload() { file.reload() }
  function accept(text) {
    if (dirty || saving) return
    var result = Config.parse(text)
    if (!result.valid) { rejectLoad(); return }
    raw = result.raw
    loaded = true
    error = ""
  }
  function save(next) {
    if (!Config.normalize(next).policyValid) {
      error = "Settings could not be saved. Check the capture settings."
      return
    }
    raw = next
    revision++
    dirty = true
    flush.restart()
  }
  function retry() { if (dirty) flush.restart() }
  function write() {
    if (saving || !dirty) return
    saving = true
    writingRevision = revision
    writingText = Config.serialize(raw)
    writer.active = true
  }
  Timer { id: flush; interval: 0; onTriggered: root.write() }
  FileView {
    id: file
    path: root.path
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.accept(text())
    onLoadFailed: function(error) {
      if (root.dirty || root.saving) return
      if (!root.loaded && !root.error && error === FileViewError.FileNotFound) root.loaded = true
      else root.rejectLoad()
    }
    onFileChanged: if (!root.dirty && !root.saving) reload()
  }
  // A fresh writer also retries identical content after a failed write;
  // FileView.setText otherwise elides unchanged cached text.
  Loader {
    id: writer
    active: false
    sourceComponent: Component {
      FileView {
        path: root.path
        atomicWrites: true
        printErrors: false
        Component.onCompleted: setText(root.writingText)
        onSaved: {
          root.saving = false
          root.loaded = true
          root.error = ""
          if (root.writingRevision === root.revision) root.dirty = false
          else flush.restart()
          writer.active = false
          root.saved()
        }
        onSaveFailed: {
          root.saving = false
          root.error = "Settings could not be saved. Changes are pending; edit a setting to retry."
          writer.active = false
        }
      }
    }
  }
}

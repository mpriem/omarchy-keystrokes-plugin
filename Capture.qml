import QtQuick
import Quickshell
import Quickshell.Io
import "CaptureProtocol.js" as Protocol

// QML watches the tmpfs snapshot and acknowledges each sequence directly.
// Child processes run only when starting/stopping/reconfiguring capture.
Item {
  id: root
  required property var config
  readonly property string settings: Protocol.optionsLua(config)
  readonly property string runtimeScript: decodeURIComponent(Qt.resolvedUrl("runtime.sh").toString().replace(/^file:\/\//, ""))
  property string directory: ""
  property string token: ""
  property string sessionSettings: ""
  property bool requested: false
  property string phase: "booting"
  readonly property bool enabled: phase === "active" && requested && !stopNeeded
  property bool initialized: false
  readonly property bool ready: initialized
  readonly property bool busy: operation !== null
  property var operation: null
  property int operationId: 0
  property int intentVersion: 0
  property var lifetime: ({ alive: true })
  property var acknowledgement: null
  property string error: ""
  property string pauseReason: ""
  property string shortcut: ""
  property bool bindingRefreshNeeded: false
  property bool stopped: false
  property bool stopAcknowledged: false
  property int cleanupAttempts: 0
  property bool cleanupBlocked: false
  property bool stopNeeded: false
  property int sequence: 0
  property int generation: -1
  signal stroke(var event)
  signal cleared()

  function refreshBinding() {
    shortcut = ""
    bindingRefreshNeeded = true
    pump()
  }
  function setEnabled(on) {
    if (on && cleanupBlocked) { error = "Capture is off; temporary-file cleanup failed."; return }
    if (!on) { cleanupAttempts = 0; cleanupBlocked = false }
    pauseReason = ""
    if (!!on === requested && !error && !pauseReason) return
    intentVersion++
    requested = !!on
    error = ""
    if (!requested) stopNeeded = true
    cleared()
    pump()
  }
  function fail(message) {
    intentVersion++
    requested = false
    stopNeeded = true
    error = message
    freshness.stop()
    cleared()
    Qt.callLater(root.pump)
  }
  function run(operation, command) {
    var next = { id: ++operationId, kind: operation, token: token, timedOut: false }
    root.operation = next
    rpc.operationId = next.id
    if (operation !== "binding" && operation !== "initial") phase = operation === "create" ? "creating" : operation === "start" ? "starting" : operation === "stop" ? "stopping" : "removing"
    rpc.command = command
    deadline.restart()
    rpc.running = true
  }
  function pump() {
    if (!ready || busy || rpc.running || cleanupRetry.running || cleanupBlocked) return
    if (directory && (!requested || stopNeeded || sessionSettings !== settings)) {
      freshness.stop()
      if (!stopped) run("stop", ["hyprctl", "repl", Protocol.stopLua(token)])
      else run("remove", ["bash", runtimeScript, "remove", directory])
    } else if (bindingRefreshNeeded) {
      run("binding", ["hyprctl", "repl", Protocol.shortcutLua()])
    } else if (!directory && requested) {
      sessionSettings = settings
      stopNeeded = false
      run("create", ["bash", runtimeScript, "create"])
    } else if (directory && requested && phase === "created") {
      run("start", ["hyprctl", "repl", Protocol.startLua(token, sessionSettings)])
    }
  }
  function finished(id, exitCode, text) {
    // A timeout keeps the operation owned until its process actually exits.
    // Old callbacks cannot affect a later session or operation.
    if (!operation || operation.id !== id) return
    var completed = operation
    if (completed.kind !== "create" && completed.token !== token) return
    deadline.stop()
    operation = null
    if (completed.timedOut) exitCode = -1
    switch (completed.kind) {
    case "initial":
      if (exitCode !== 0) fail("Capture initialization unavailable.")
      shortcut = exitCode === 0 ? Protocol.shortcutLabel(text) : ""
      phase = "off"
      initialized = true
      break
    case "binding":
      shortcut = exitCode === 0 ? Protocol.shortcutLabel(text) : ""
      bindingRefreshNeeded = false
      break
    case "create":
      var path = text.trim()
      var prefix = Quickshell.env("XDG_RUNTIME_DIR") + "/omarchy-keystrokes."
      if ((!completed.timedOut && exitCode !== 0) || path.indexOf(prefix) !== 0 || !/^[A-Za-z0-9]{12}$/.test(path.slice(prefix.length))) {
        phase = "off"
        fail("Cannot create private tmpfs files. Check XDG_RUNTIME_DIR and its permissions.")
        break
      }
      token = path.slice(prefix.length)
      sequence = 0
      generation = -1
      phase = "created"
      stopped = false
      stopAcknowledged = false
      cleanupAttempts = 0
      acknowledgement = ackComponent.createObject(root, { session: token, directory: path })
      directory = path
      break
    case "start":
      if (phase !== "active") phase = "waiting"
      if (exitCode !== 0 || text.trim() !== "keystrokes-v5 waiting") {
        fail("Capture unavailable. Check the Lua setup and reload Hyprland.")
      } else if (requested && !stopNeeded) freshness.restart()
      break
    case "stop":
      stopped = true
      stopAcknowledged = exitCode === 0 && text.trim() === "keystrokes-v5 off"
      if (!stopAcknowledged) {
        requested = false
        error = "Capture is off; backend stop was not acknowledged."
        cleanupRetry.interval = 1100
        cleanupRetry.restart()
      }
      break
    case "remove":
      if (exitCode !== 0) {
        cleanupAttempts++
        fail("Capture is off; temporary-file cleanup failed.")
        if (cleanupAttempts < 3) { cleanupRetry.interval = 100; cleanupRetry.restart() }
        else cleanupBlocked = true
        break
      }
      if (acknowledgement) acknowledgement.destroy()
      acknowledgement = null
      directory = ""
      token = ""
      phase = "off"
      stopped = false
      stopNeeded = false
      break
    }
    Qt.callLater(root.pump)
  }
  function accepting() {
    return requested && !stopNeeded && directory !== "" && sessionSettings === settings
      && ["starting", "waiting", "active"].indexOf(phase) >= 0
  }
  function receive(text) {
    if (!accepting()) return
    var version = intentVersion, session = token, guard = lifetime
    var frame = Protocol.parse(text, token)
    if (!frame || frame.sequence <= sequence) return
    sequence = frame.sequence
    if (generation !== frame.generation) { generation = frame.generation; cleared() }
    if (!guard.alive || !accepting() || version !== intentVersion || session !== token) return
    shortcut = frame.shortcut
    phase = frame.enabled ? "active" : "waiting"
    if (frame.pauseReason) {
      pauseReason = frame.pauseReason
      requested = false
      stopNeeded = true
      freshness.stop()
      cleared()
      Qt.callLater(root.pump)
      return
    }
    for (var line of frame.events) {
      if (!guard.alive || !accepting() || version !== intentVersion || session !== token) return
      stroke(line)
    }
    if (!guard.alive || !accepting() || version !== intentVersion || session !== token) return
    acknowledgement.setText(token + " " + sequence + "\n")
    freshness.restart()
  }

  onSettingsChanged: if (ready && requested) {
    intentVersion++
    stopNeeded = true
    cleared()
    pump()
  }
  Component.onCompleted: run("initial", ["hyprctl", "repl", "if Keystrokes then Keystrokes.set(false) end; " + Protocol.shortcutLua()])
  Component.onDestruction: {
    lifetime.alive = false
    if (directory) Quickshell.execDetached(["bash", runtimeScript, "cleanup", directory])
  }

  FileView {
    id: snapshot
    path: root.directory ? root.directory + "/events" : ""
    watchChanges: true
    printErrors: false
    onLoaded: root.receive(text())
    onFileChanged: reload()
    onLoadFailed: if (root.directory && root.requested && !root.stopNeeded) retryRead.restart()
  }
  Component {
    id: ackComponent
    FileView {
      required property string session
      required property string directory
      path: directory + "/ack"
      // Each writer owns an immutable session/path; late failures cannot stop
      // a newer session. Retain the pre-created mode-0600 ACK inode.
      atomicWrites: false
      printErrors: false
      onSaveFailed: if (session === root.token && root.accepting())
        root.fail("Capture stopped because its acknowledgement could not be written.")
    }
  }
  Timer { id: cleanupRetry; interval: 100; onTriggered: root.pump() }
  Timer { id: retryRead; interval: 20; onTriggered: if (root.directory && root.requested) snapshot.reload() }
  Timer { id: freshness; interval: 1500; onTriggered: root.fail("Capture stopped responding. Turn it on again to retry.") }
  Process {
    id: rpc
    property int operationId: 0
    stdout: StdioCollector { id: output; waitForEnd: true }
    stderr: StdioCollector {}
    onExited: function(exitCode) { root.finished(operationId, exitCode, output.text) }
  }
  Timer {
    id: deadline
    interval: 2000
    onTriggered: {
      if (!root.operation) return
      root.operation.timedOut = true
      root.fail("Capture setup timed out.")
      rpc.signal(9)
    }
  }
}

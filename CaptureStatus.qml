pragma Singleton
import QtQuick

// The two plugin entry points share a QML engine in the host shell. Publish
// state by binding instead of launching a status process for every widget.
// A separately hosted panel keeps the existing bounded IPC fallback.
QtObject {
  property var source: null
  readonly property var state: source ? source.captureState : null
}

import QtQuick
import "StrokeHistory.js" as History

Item {
  id: root
  required property var config
  property var entries: []
  readonly property var rows: History.display(History.limit(entries, config.maxItems), config.order)
  readonly property int count: entries.length
  function clear() { entries = [] }
  function ingest(event) { entries = History.append(entries, event, config, Date.now()) }
  function prune() { entries = History.expire(entries, Date.now(), config.timeoutMs) }
  function reconcile() { entries = History.limit(entries, config.maxItems) }
  onConfigChanged: Qt.callLater(root.reconcile)
  Timer { interval: 200; repeat: true; running: root.count > 0; onTriggered: root.prune() }
}

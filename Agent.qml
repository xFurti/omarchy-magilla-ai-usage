import QtQuick
import Quickshell.Io

// One usage record on disk. Magilla never parses provider formats here —
// a JSON file in the usage directory is an agent, whoever wrote it.
Item {
  id: root
  visible: false

  property string agentId: ""
  property string path: ""
  property var record: null
  property string visualKey: ""

  FileView {
    path: root.path
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parse(text())
    onLoadFailed: root.clearRecord()
  }

  // Collectors rewrite every record with a fresh updatedAt. Comparing the
  // rest keeps an unchanged quota from rebuilding the bars.
  function visualSignature(parsed) {
    if (!parsed) return ""
    var copy = {}
    for (var key in parsed) if (key !== "updatedAt") copy[key] = parsed[key]
    return JSON.stringify(copy)
  }

  function clearRecord() {
    if (root.record === null && root.visualKey === "") return
    root.visualKey = ""
    root.record = null
  }

  function parse(content) {
    try {
      var parsed = JSON.parse(String(content || ""))
      if (!parsed || typeof parsed !== "object") {
        root.clearRecord()
        return
      }
      var key = root.visualSignature(parsed)
      if (key === root.visualKey) return
      root.visualKey = key
      root.record = parsed
    } catch (e) {
      console.warn("magilla-ai-usage", "Ignoring bad usage record", root.path, e)
      root.clearRecord()
    }
  }
}

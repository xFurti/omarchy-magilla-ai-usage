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

  FileView {
    path: root.path
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parse(text())
    onLoadFailed: root.record = null
  }

  function parse(content) {
    try {
      var parsed = JSON.parse(String(content || ""))
      root.record = parsed && typeof parsed === "object" ? parsed : null
    } catch (e) {
      console.warn("magilla-ai-usage", "Ignoring bad usage record", root.path, e)
      root.record = null
    }
  }
}

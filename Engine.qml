import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Detection + usage engine. UI files bind to providers / barProviders and
// call refresh(); all filesystem and collector work stays here.
Item {
  id: root
  visible: false

  property var settings: ({})
  property double nowMs: Date.now()

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateHome: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state")
  readonly property string magillaDir: stateHome + "/magilla-ai-usage"
  readonly property string usageDir: magillaDir + "/usage"
  readonly property string omarchyUsageDir: stateHome + "/omarchy/agents/usage"
  readonly property string detectedPath: magillaDir + "/detected.json"
  readonly property string pluginDir: Model.pluginPathFromUrl(Qt.resolvedUrl("."))
  readonly property string updaterPath: pluginDir + "/collectors/magilla-usage-update"

  property var catalog: ({ providers: [] })
  property var records: ({})
  property var magillaIds: []
  property var omarchyIds: []
  property int dataRevision: 0
  property bool refreshing: false
  property string lastRefreshAt: ""
  property string lastError: ""

  readonly property var providers: {
    var rev = dataRevision
    return Model.mergeProviders(catalog, records, settings)
  }

  readonly property var panelProviders: {
    var list = []
    var all = root.providers
    for (var i = 0; i < all.length; i++) {
      if (all[i].visibleInPanel) list.push(all[i])
    }
    return list
  }

  readonly property var barProviders: Model.resolveBarProviders(root.providers, settings)

  readonly property int refreshIntervalSec: Math.max(30, Number(settings && settings.refreshIntervalSec ? settings.refreshIntervalSec : 300))

  FileView {
    id: detectedFile
    path: root.detectedPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parseCatalog(text())
    onLoadFailed: root.catalog = ({ providers: [] })
  }

  function parseCatalog(content) {
    try {
      var parsed = JSON.parse(String(content || ""))
      root.catalog = parsed && typeof parsed === "object" ? parsed : ({ providers: [] })
    } catch (e) {
      console.warn("magilla-ai-usage", "Ignoring bad detection catalog", e)
      root.catalog = ({ providers: [] })
    }
    root.dataRevision++
  }

  Process {
    id: magillaList
    running: false
    command: ["find", root.usageDir, "-maxdepth", "1", "-name", "*.json", "-printf", "%f\n"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyListing(text, "magilla")
    }
  }

  Process {
    id: omarchyList
    running: false
    command: ["find", root.omarchyUsageDir, "-maxdepth", "1", "-name", "*.json", "-printf", "%f\n"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyListing(text, "omarchy")
    }
  }

  function rescanRecords() {
    if (!magillaList.running) magillaList.running = true
    if (!omarchyList.running) omarchyList.running = true
  }

  function applyListing(output, source) {
    var ids = []
    var lines = String(output || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var name = lines[i].trim()
      if (name.slice(-5) === ".json") ids.push(name.slice(0, -5))
    }
    ids.sort()
    if (source === "magilla") {
      if (JSON.stringify(ids) !== JSON.stringify(magillaIds)) magillaIds = ids
    } else if (JSON.stringify(ids) !== JSON.stringify(omarchyIds)) {
      omarchyIds = ids
    }
  }

  Instantiator {
    id: magillaAgents
    model: root.magillaIds
    delegate: Agent {
      required property var modelData
      agentId: modelData
      path: root.usageDir + "/" + modelData + ".json"
      onRecordChanged: root.rebuildRecords()
    }
    onObjectAdded: (index, object) => root.rebuildRecords()
    onObjectRemoved: (index, object) => root.rebuildRecords()
  }

  Instantiator {
    id: omarchyAgents
    model: root.omarchyIds
    delegate: Agent {
      required property var modelData
      agentId: modelData
      path: root.omarchyUsageDir + "/" + modelData + ".json"
      onRecordChanged: root.rebuildRecords()
    }
    onObjectAdded: (index, object) => root.rebuildRecords()
    onObjectRemoved: (index, object) => root.rebuildRecords()
  }

  function rebuildRecords() {
    var next = {}
    function absorb(instantiator) {
      for (var i = 0; i < instantiator.count; i++) {
        var agent = instantiator.objectAt(i)
        if (!agent || !agent.record || !agent.record.id) continue
        var id = String(agent.record.id)
        // Magilla's own copy wins over a stale Omarchy record of the same id.
        if (next[id] && instantiator === omarchyAgents) continue
        next[id] = agent.record
      }
    }
    absorb(omarchyAgents)
    absorb(magillaAgents)
    records = next
    dataRevision++
  }

  Process {
    id: updateProcess
    running: false
    onRunningChanged: root.refreshing = running
    onExited: {
      root.lastRefreshAt = new Date().toISOString()
      detectedFile.reload()
      root.rescanRecords()
      if (root.pendingKind !== "") {
        var kind = root.pendingKind
        root.pendingKind = ""
        root.runUpdate(kind)
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (text.trim() !== "") {
          root.lastError = text.trim()
          console.warn("magilla-ai-usage", text.trim())
        }
      }
    }
  }

  property string pendingKind: ""

  function runUpdate(kind) {
    if (updateProcess.running) {
      if (kind === "force" || root.pendingKind === "") root.pendingKind = kind
      return
    }
    var command = ["python3", root.updaterPath]
    if (kind === "force") command.push("--force")
    if (kind === "limits") command.push("--limits-only")
    updateProcess.command = command
    updateProcess.running = true
  }

  function refresh() { runUpdate("force") }
  function refreshLimits() { runUpdate("limits") }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.runUpdate("normal")
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  Component.onCompleted: {
    rescanRecords()
    detectedFile.reload()
  }

  function colorChannelLuminance(value) {
    var channel = Number(value)
    if (!isFinite(channel)) return 0
    return channel <= 0.03928 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4)
  }

  function colorLuminance(color) {
    return 0.2126 * colorChannelLuminance(color.r)
      + 0.7152 * colorChannelLuminance(color.g)
      + 0.0722 * colorChannelLuminance(color.b)
  }

  function iconUrl(providerId, surfaceColor) {
    var id = String(providerId || "")
    if (id === "crush") return Qt.resolvedUrl("assets/icons/crush.png")
    var lightSurface = false
    if (surfaceColor !== undefined && surfaceColor !== null)
      lightSurface = colorLuminance(surfaceColor) >= 0.5
    if (lightSurface && (id === "grok" || id === "codex" || id === "copilot" || id === "pi"))
      return Qt.resolvedUrl("assets/icons/" + id + "-light.svg")
    return Qt.resolvedUrl("assets/icons/" + id + ".svg")
  }

  function magillaUrl() {
    return Qt.resolvedUrl("assets/magilla-mark.png")
  }

  function magillaFullUrl() {
    return Qt.resolvedUrl("assets/magilla.png")
  }
}

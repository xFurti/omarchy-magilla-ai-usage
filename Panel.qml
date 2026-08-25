import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Signed-in usage dashboard. Matches Omarchy Agents: one hero, meters, switch.
Panel {
  id: root
  moduleName: "io.github.xfurti.magilla-ai-usage"
  ipcTarget: "io.github.xfurti.magilla-ai-usage"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var engine: null
  readonly property var barIdentity: hostWidget || root

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(contentForeground, 1.55)
  readonly property color surface: Color.popups.background
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color track: Style.selectedFillFor(contentForeground, Color.accent)

  property bool settingsOpen: false
  property string selectedProviderId: ""
  property bool cursorActive: false

  readonly property var providers: engine ? engine.panelProviders : []
  readonly property int providerIndex: {
    for (var i = 0; i < providers.length; i++)
      if (providers[i].providerId === selectedProviderId) return i
    return 0
  }
  readonly property var provider: providers.length > 0 ? providers[Math.max(0, providerIndex)] : null
  readonly property var limits: provider ? (provider.limits || []) : []
  readonly property var models: Model.modelRows(provider)
  readonly property var headline: provider ? provider.headline : null
  readonly property bool alarming: !!(headline && headline.percent >= 0.9)

  function clamp(v, lo, hi) {
    var n = Number(v)
    if (!isFinite(n)) n = lo
    return Math.max(lo, Math.min(hi, n))
  }
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  function limitPercent(entry) {
    var p = Number(entry && entry.percent)
    if (!isFinite(p) || p < 0) return -1
    return p > 1 ? Math.min(1, p / 100) : Math.min(1, p)
  }

  function meterColor(percent) {
    if (percent >= 0.9) return root.urgent
    if (percent >= 0.8) return root.urgent
    return root.contentForeground
  }

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]
    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function selectProvider(index) {
    if (providers.length === 0) return
    var wrapped = ((index % providers.length) + providers.length) % providers.length
    selectedProviderId = providers[wrapped].providerId
  }

  function open() {
    root.settingsOpen = false
    if (engine && engine.refreshLimits) engine.refreshLimits()
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
      if (keyCatcher) keyCatcher.forceActiveFocus()
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.settingsOpen = false
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function refresh() {
    if (engine) engine.refresh()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function heroMeta(p) {
    if (!p) return ""
    if (String(p.usageStatusText || "") !== "") return p.usageStatusText
    return String(p.tierLabel || "")
  }

  onProviderIndexChanged: if (panelFlick) panelFlick.contentY = 0
  onOpenedChanged: if (opened) {
    cursorActive = false
    if (panelFlick) panelFlick.contentY = 0
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: {
        if (root.settingsOpen) root.settingsOpen = false
        else root.close()
      }
      onActivateRequested: root.refresh()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refresh()
        else if (t === "s" || t === "S") root.settingsOpen = !root.settingsOpen
      }
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) {
          root.cursorActive = true
          root.selectProvider(root.providerIndex + dx)
        }
        if (dy !== 0)
          panelFlick.contentY = root.clamp(panelFlick.contentY + dy * Style.space(56), 0,
                                           Math.max(0, panelFlick.contentHeight - panelFlick.height))
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Row {
            visible: !root.settingsOpen
            width: parent.width
            spacing: Style.space(10)

            Image {
              width: Style.space(28)
              height: Style.space(28)
              anchors.verticalCenter: parent.verticalCenter
              source: engine ? engine.magillaUrl() : ""
              sourceSize.width: Style.space(56)
              sourceSize.height: Style.space(56)
              fillMode: Image.PreserveAspectFit
            }

            Column {
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(1)

              Text {
                text: "Magilla"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
              }

              Text {
                text: engine && engine.refreshing ? "Refreshing" : (engine && engine.lastRefreshAt ? Model.formatClock(engine.lastRefreshAt) : "")
                color: root.dim
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          PanelHero {
            visible: !root.settingsOpen && !!root.provider
            width: parent.width
            title: root.provider ? root.provider.providerName : ""
            meta: root.heroMeta(root.provider)
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily

            iconComponent: Component {
              Image {
                width: Style.font.display
                height: Style.font.display
                source: engine && root.provider ? engine.iconUrl(root.provider.providerId, root.surface) : ""
                sourceSize.width: Style.font.display * 2
                sourceSize.height: Style.font.display * 2
                fillMode: Image.PreserveAspectFit
              }
            }

            trailingControl: Component {
              Row {
                spacing: Style.space(2)

                PanelActionButton {
                  iconText: "󰑐"
                  tooltipText: "Refresh"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: root.refresh()
                }

                PanelActionButton {
                  iconText: "󰒓"
                  tooltipText: "Settings"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: root.settingsOpen = true
                }
              }
            }
          }

          Row {
            visible: root.settingsOpen
            width: parent.width
            spacing: Style.space(8)

            Button {
              text: "Back"
              bordered: true
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              fontSize: Style.font.bodySmall
              onClicked: root.settingsOpen = false
            }

            Button {
              text: engine && engine.refreshing ? "Refreshing…" : "Refresh"
              bordered: true
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              fontSize: Style.font.bodySmall
              onClicked: root.refresh()
            }
          }

          Loader {
            width: parent.width
            active: root.settingsOpen
            visible: root.settingsOpen
            source: Qt.resolvedUrl("Settings.qml")
            onLoaded: {
              item.engine = root.engine
              item.host = root
            }
          }

          Column {
            visible: !root.settingsOpen
            width: parent.width
            spacing: Style.space(12)

            Text {
              visible: !root.provider
              width: parent.width
              topPadding: Style.space(20)
              text: "No signed-in coding agents.\nSign in to Grok, Cursor, Claude, or Codex and they will appear here."
              color: root.dim
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
            }

            Row {
              id: providerSwitch
              visible: root.providers.length > 1
              width: parent.width
              spacing: Style.spacing.md

              readonly property real cellWidth: root.providers.length > 0
                ? (width - spacing * (root.providers.length - 1)) / root.providers.length
                : 0

              Repeater {
                model: root.providers

                Button {
                  required property var modelData
                  required property int index
                  width: providerSwitch.cellWidth
                  text: modelData.shortName
                  selected: index === root.providerIndex
                  hasCursor: root.cursorActive && index === root.providerIndex
                  bordered: true
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  fontSize: Style.font.bodySmall
                  verticalPadding: Style.spacing.controlPaddingY
                  onClicked: {
                    root.cursorActive = true
                    root.selectProvider(index)
                  }
                }
              }
            }

            BorderSurface {
              visible: !!root.provider && String(root.provider.authHelpText || "") !== ""
              width: parent.width
              implicitHeight: statusText.implicitHeight + Style.spacing.xl * 2
              color: root.alpha(root.urgent, 0.10)
              borderSpec: Border.flat(root.alpha(root.urgent, 0.35), 1)
              radius: Style.cornerRadius

              Text {
                id: statusText
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                text: root.provider ? String(root.provider.authHelpText || "") : ""
                color: root.dim
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }

            Column {
              visible: root.limits.length > 0
              width: parent.width
              spacing: Style.space(10)

              PanelSectionHeader {
                text: "LIMITS"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
              }

              Repeater {
                model: root.limits

                Column {
                  required property var modelData
                  width: parent.width
                  spacing: Style.space(6)

                  readonly property real pct: root.limitPercent(modelData)

                  Item {
                    width: parent.width
                    implicitHeight: Math.max(limitLabel.implicitHeight, limitValue.implicitHeight)

                    Text {
                      id: limitLabel
                      text: String(modelData.title || modelData.label || "Limit")
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                      anchors.left: parent.left
                      anchors.right: limitValue.left
                      anchors.rightMargin: Style.spacing.sm
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                      id: limitValue
                      text: parent.parent.pct >= 0 ? Math.round(parent.parent.pct * 100) + "%" : "—"
                      color: root.meterColor(parent.parent.pct)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                    }
                  }

                  Meter {
                    width: parent.width
                    value: parent.pct
                    fill: root.meterColor(parent.pct)
                  }

                  Text {
                    visible: text !== ""
                    width: parent.width
                    text: Model.formatReset(modelData.resetsAt, engine ? engine.nowMs : Date.now())
                    color: root.dim
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }

            Text {
              visible: !!root.provider && root.provider.balance
              width: parent.width
              text: {
                if (!root.provider || !root.provider.balance) return ""
                var b = root.provider.balance
                return "Prepaid " + Number(b.remaining).toFixed(2) + " " + String(b.currency || "USD") + " remaining"
              }
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              visible: !!root.provider && root.provider.hasLocalStats
              width: parent.width
              text: root.provider
                ? Model.formatTokenCount(root.provider.todayTotalTokens) + " tokens today · "
                  + root.provider.todayPrompts + " prompts"
                : ""
              color: root.dim
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
            }

            Column {
              visible: root.models.length > 0
              width: parent.width
              spacing: Style.spacing.md

              PanelSeparator { foreground: root.contentForeground }

              PanelSectionHeader {
                text: "MODELS"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
              }

              Repeater {
                model: root.models

                Item {
                  required property var modelData
                  width: parent.width
                  implicitHeight: modelName.implicitHeight + Style.spacing.lg

                  Rectangle {
                    anchors.fill: parent
                    radius: Style.cornerRadius
                    color: root.alpha(root.contentForeground, 0.05)
                  }

                  Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * root.clamp(modelData.total / Math.max(1, root.models[0].total), 0, 1)
                    radius: Style.cornerRadius
                    color: root.alpha(root.contentForeground, 0.14)
                  }

                  Text {
                    id: modelName
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.name
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    text: Model.formatTokenCount(modelData.total)
                    color: root.dim
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  component Meter: Item {
    id: meter
    property real value: -1
    property color fill: root.contentForeground
    property real thickness: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))
    implicitHeight: thickness

    Rectangle {
      id: meterTrack
      anchors.fill: parent
      radius: height / 2
      color: root.track

      Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        radius: meterTrack.radius
        width: meterTrack.width * root.clamp(meter.value, 0, 1)
        color: meter.fill
        Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
      }
    }
  }
}

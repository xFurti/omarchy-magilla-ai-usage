import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "Theme.js" as Theme

// Magilla dashboard. BarWidget.qml owns the bar chip and injects this panel.
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
  readonly property color magilla: Style.colorFromHex(Theme.purple, Color.accent)
  readonly property color banana: Style.colorFromHex(Theme.banana, Color.accent)

  property bool settingsOpen: false
  property string selectedProviderId: ""

  readonly property var providers: engine ? engine.panelProviders : []
  readonly property var overview: engine ? engine.barProviders : []
  readonly property var selected: {
    for (var i = 0; i < providers.length; i++) {
      if (providers[i].providerId === selectedProviderId) return providers[i]
    }
    return providers.length > 0 ? providers[0] : null
  }

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]
    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
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

  function pinProvider(id, on) {
    persistSettings({ barSlots: Model.joinBarSlots(Model.pinSlots(root.settings.barSlots, id, on)) })
  }

  function formatRefresh() {
    if (!engine || !engine.lastRefreshAt) return engine && engine.refreshing ? "Refreshing…" : "Not yet refreshed"
    return "Updated " + Model.formatClock(engine.lastRefreshAt)
  }

  function statusColor(status) {
    return Style.colorFromHex(Theme.statusHex(status), contentForeground)
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(640))

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
        if (dy !== 0)
          panelFlick.contentY = root.clamp(panelFlick.contentY + dy * Style.space(56), 0,
                                           Math.max(0, panelFlick.contentHeight - panelFlick.height))
        if (dx !== 0 && providers.length > 0) {
          var index = 0
          for (var i = 0; i < providers.length; i++) if (providers[i] === root.selected) index = i
          var next = ((index + dx) % providers.length + providers.length) % providers.length
          root.selectedProviderId = providers[next].providerId
        }
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
            width: parent.width
            spacing: Style.space(12)

            Image {
              width: Style.space(42)
              height: Style.space(42)
              source: engine ? engine.magillaFullUrl() : ""
              sourceSize.width: Style.space(84)
              sourceSize.height: Style.space(84)
              fillMode: Image.PreserveAspectFit
            }

            Column {
              width: parent.width - Style.space(54)
              spacing: Style.space(2)
              anchors.verticalCenter: parent.verticalCenter

              Text {
                text: "MAGILLA AI USAGE"
                color: root.magilla
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1.4
                font.bold: true
              }

              Text {
                text: "Subscriptions, leftovers, and reset times"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                text: root.formatRefresh()
                color: root.dim
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            Button {
              text: root.settingsOpen ? "Overview" : "Magilla Settings"
              bordered: true
              selected: root.settingsOpen
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              fontSize: Style.font.bodySmall
              onClicked: root.settingsOpen = !root.settingsOpen
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
            id: settingsLoader
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
              visible: root.providers.length === 0
              width: parent.width
              topPadding: Style.space(16)
              text: "No AI coding tools found yet.\nMagilla looks for Grok, Cursor, Claude Code, Codex, OpenCode, and friends."
              color: root.dim
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
            }

            PanelSectionHeader {
              visible: overviewRepeater.count > 0
              width: parent.width
              text: "ON THE BAR"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
            }

            Row {
              id: overviewRow
              visible: overviewRepeater.count > 0
              width: parent.width
              spacing: Style.space(8)

              Repeater {
                id: overviewRepeater
                model: root.overview

                BorderSurface {
                  required property var modelData
                  width: overviewRepeater.count > 0
                    ? (overviewRow.width - overviewRow.spacing * (overviewRepeater.count - 1)) / overviewRepeater.count
                    : overviewRow.width
                  implicitHeight: cardCol.implicitHeight + Style.space(16)
                  radius: Math.max(Style.cornerRadius, 8)
                  color: root.alpha(root.statusColor(modelData.status), 0.12)
                  borderSpec: Border.flat(root.alpha(root.statusColor(modelData.status), 0.45), 1)

                  Column {
                    id: cardCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Style.space(10)
                    spacing: Style.space(6)

                    Row {
                      spacing: Style.space(6)
                      Image {
                        width: Style.space(14)
                        height: Style.space(14)
                        source: engine.iconUrl(modelData.providerId)
                        sourceSize.width: Style.space(28)
                        sourceSize.height: Style.space(28)
                      }
                      Text {
                        text: modelData.shortName
                        color: root.contentForeground
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }
                    }

                    Text {
                      text: modelData.usedPercent >= 0 ? Model.formatPercent(modelData.usedPercent) : "—"
                      color: root.statusColor(modelData.status)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.heading
                      font.bold: true
                    }

                    Meter {
                      width: parent.width
                      value: modelData.usedPercent
                      fill: root.statusColor(modelData.status)
                    }

                    Text {
                      width: parent.width
                      text: modelData.headline && modelData.headline.resetsAt
                        ? Model.formatReset(modelData.headline.resetsAt, engine.nowMs)
                        : modelData.statusLabel
                      color: root.dim
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.selectedProviderId = modelData.providerId
                  }
                }
              }
            }

            PanelSeparator {
              visible: root.providers.length > 0
              foreground: root.contentForeground
            }

            PanelSectionHeader {
              visible: root.providers.length > 0
              width: parent.width
              text: "ALL PROVIDERS"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
            }

            Repeater {
              model: root.providers

              ProviderCard {
                required property var modelData
                width: column.width
                provider: modelData
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
      anchors.fill: parent
      radius: height / 2
      color: root.alpha(root.magilla, 0.18)
    }

    Rectangle {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      height: parent.height
      radius: parent.radius
      width: parent.width * root.clamp(meter.value, 0, 1)
      color: meter.value < 0 ? "transparent" : meter.fill
      Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }
  }

  component ProviderCard: BorderSurface {
    id: card
    property var provider: null

    readonly property bool selected: root.selected && provider && root.selected.providerId === provider.providerId
    readonly property var pinned: Model.parseBarSlots(root.settings.barSlots)
    readonly property bool onBar: provider && pinned.indexOf(provider.providerId) >= 0
    readonly property var models: Model.modelRows(provider)

    radius: Math.max(Style.cornerRadius, 8)
    color: selected ? root.alpha(root.magilla, 0.10) : Style.controlFill(false, false, root.contentForeground, Color.accent)
    borderSpec: selected
      ? Border.flat(root.alpha(root.magilla, 0.55), 1)
      : Border.controlSpec("normal", root.contentForeground, Color.accent)
    implicitHeight: body.implicitHeight + Style.space(18)

    MouseArea {
      anchors.fill: parent
      z: -1
      onClicked: if (card.provider) root.selectedProviderId = card.provider.providerId
    }

    Column {
      id: body
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.space(12)
      spacing: Style.space(8)

      Row {
        width: parent.width
        spacing: Style.space(8)

        Image {
          width: Style.space(20)
          height: Style.space(20)
          anchors.verticalCenter: parent.verticalCenter
          source: engine ? engine.iconUrl(card.provider.providerId) : ""
          sourceSize.width: Style.space(40)
          sourceSize.height: Style.space(40)
        }

        Column {
          width: parent.width - Style.space(28)
          spacing: Style.space(1)

          Row {
            width: parent.width
            spacing: Style.space(8)

            Text {
              text: card.provider ? card.provider.providerName : ""
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }

            BorderSurface {
              visible: card.provider && card.provider.tierLabel !== ""
              implicitWidth: tierText.implicitWidth + Style.space(10)
              implicitHeight: tierText.implicitHeight + Style.space(4)
              color: root.alpha(root.banana, 0.16)
              radius: Style.cornerRadius

              Text {
                id: tierText
                anchors.centerIn: parent
                text: card.provider ? card.provider.tierLabel : ""
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Item { width: 1; height: 1 }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: card.provider ? card.provider.statusLabel : ""
              color: card.provider ? root.statusColor(card.provider.status) : root.dim
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          Text {
            width: parent.width
            visible: card.provider && (card.provider.usageStatusText !== "" || card.provider.authHelpText !== "")
            text: card.provider ? (card.provider.authHelpText || card.provider.usageStatusText) : ""
            color: root.dim
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }

      Repeater {
        model: card.provider ? (card.provider.limits || []) : []

        Column {
          required property var modelData
          width: body.width
          spacing: Style.space(4)

          Item {
            width: parent.width
            implicitHeight: Math.max(limitTitle.implicitHeight, limitPct.implicitHeight)

            Text {
              id: limitTitle
              text: String(modelData.title || modelData.label || "Limit")
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: limitPct
              text: Model.formatPercent(Number(modelData.percent) > 1 ? Number(modelData.percent) / 100 : Number(modelData.percent))
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          Meter {
            width: parent.width
            value: Number(modelData.percent) > 1 ? Number(modelData.percent) / 100 : Number(modelData.percent)
            fill: root.statusColor(card.provider ? card.provider.status : "idle")
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

      Text {
        visible: card.provider && card.provider.balance
        width: parent.width
        text: {
          if (!card.provider || !card.provider.balance) return ""
          var b = card.provider.balance
          return "Prepaid " + Number(b.remaining).toFixed(2) + " " + String(b.currency || "USD") + " left"
        }
        color: root.contentForeground
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        visible: card.provider && card.provider.hasLocalStats
        width: parent.width
        text: card.provider
          ? "Today " + Model.formatTokenCount(card.provider.todayTotalTokens) + " tokens · "
            + card.provider.todayPrompts + " prompts · " + card.provider.todaySessions + " sessions"
          : ""
        color: root.dim
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      Repeater {
        model: card.selected ? card.models : []

        Row {
          required property var modelData
          width: body.width
          spacing: Style.space(8)

          Text {
            width: parent.width - Style.space(64)
            text: modelData.name
            color: root.dim
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          Text {
            text: Model.formatTokenCount(modelData.total)
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }
      }

      Row {
        spacing: Style.space(8)

        Button {
          text: card.onBar ? "Unpin from bar" : "Pin to bar"
          bordered: true
          selected: card.onBar
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          fontSize: Style.font.caption
          onClicked: root.pinProvider(card.provider.providerId, !card.onBar)
        }
      }
    }
  }
}

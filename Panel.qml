import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Stacked usage cards for signed-in providers with live quota.
// Unsigned installs live in Settings.
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
  readonly property color track: Style.selectedFillFor(contentForeground, Color.accent)
  readonly property color fill: Color.accent
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  property bool settingsOpen: false

  readonly property var providers: engine ? engine.panelProviders : []

  function clamp(v, lo, hi) {
    var n = Number(v)
    if (!isFinite(n)) n = lo
    return Math.max(lo, Math.min(hi, n))
  }

  function limitPercent(entry) {
    var p = Number(entry && entry.percent)
    if (!isFinite(p) || p < 0) return -1
    return p > 1 ? Math.min(1, p / 100) : Math.min(1, p)
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

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
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
          spacing: Style.space(14)

          Item {
            width: parent.width
            implicitHeight: Style.space(28)

            Image {
              visible: !root.settingsOpen
              width: Style.space(22)
              height: Style.space(22)
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              source: engine ? engine.magillaUrl() : ""
              sourceSize.width: Style.space(44)
              sourceSize.height: Style.space(44)
              fillMode: Image.PreserveAspectFit
            }

            Text {
              visible: root.settingsOpen
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "Settings"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              PanelActionButton {
                visible: root.settingsOpen
                iconText: "󰅁"
                tooltipText: "Back"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.settingsOpen = false
              }

              PanelActionButton {
                iconText: "󰑐"
                tooltipText: "Refresh"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.refresh()
              }

              PanelActionButton {
                visible: !root.settingsOpen
                iconText: "󰒓"
                tooltipText: "Settings"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.settingsOpen = true
              }
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
            spacing: Style.space(16)

            Text {
              visible: root.providers.length === 0
              width: parent.width
              topPadding: Style.space(16)
              text: "No signed-in usage yet.\nOpen Settings to see installed tools."
              color: root.dim
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
            }

            Repeater {
              model: root.providers

              ProviderCard {
                required property var modelData
                required property int index
                width: column.width
                provider: modelData
                showDivider: index > 0
              }
            }
          }
        }
      }
    }
  }

  component ProviderCard: Column {
    id: card
    property var provider: null
    property bool showDivider: false
    spacing: Style.space(12)

    readonly property var limits: provider && provider.limits ? provider.limits : []
    readonly property string planName: {
      if (!provider) return ""
      if (provider.tierLabel) return provider.tierLabel
      return provider.providerName || ""
    }

    PanelSeparator {
      visible: card.showDivider
      foreground: root.contentForeground
    }

    Item {
      width: parent.width
      implicitHeight: Math.max(planIcon.height, planTitle.implicitHeight)

      Image {
        id: planIcon
        width: Style.font.display
        height: planTitle.height
        anchors.left: parent.left
        anchors.top: parent.top
        source: engine && card.provider ? engine.iconUrl(card.provider.providerId, root.surface) : ""
        sourceSize.width: Style.font.display * 2
        sourceSize.height: Style.font.display * 2
        fillMode: Image.PreserveAspectFit
      }

      Text {
        id: planTitle
        anchors.left: planIcon.right
        anchors.leftMargin: Style.space(14)
        anchors.right: parent.right
        anchors.verticalCenter: planIcon.verticalCenter
        text: card.planName
        textFormat: Text.PlainText
        color: root.contentForeground
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.title
        font.bold: true
        elide: Text.ElideRight
      }
    }

    Repeater {
      model: card.limits

      Column {
        required property var modelData
        required property int index
        width: card.width
        spacing: Style.space(6)

        readonly property real pct: root.limitPercent(modelData)
        readonly property bool hot: pct >= 0.9

        Item {
          width: parent.width
          implicitHeight: Math.max(usedText.implicitHeight, resetText.implicitHeight)

          Text {
            id: usedText
            width: parent.width - (resetText.visible ? resetText.implicitWidth + Style.space(10) : 0)
            text: Model.usedLabel(modelData)
            color: parent.parent.hot ? root.urgent : root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            id: resetText
            visible: index === 0 && text !== ""
            text: Model.formatResetsLabel(modelData.resetsAt)
            color: root.dim
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideLeft
            horizontalAlignment: Text.AlignRight
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Meter {
          width: parent.width
          value: parent.pct
          fill: parent.hot ? root.urgent : root.fill
        }
      }
    }

    Text {
      visible: card.provider && card.provider.hasLocalStats && Number(card.provider.todayTotalTokens) > 0
      width: parent.width
      text: card.provider
        ? Model.formatTokenCount(card.provider.todayTotalTokens) + " tokens today"
        : ""
      color: root.dim
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.caption
    }
  }

  component Meter: Item {
    id: meter
    property real value: -1
    property color fill: root.fill
    implicitHeight: Math.max(Style.space(6), Math.round(Style.spacing.controlHeight * 0.18))

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

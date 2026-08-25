import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "Theme.js" as Theme

// Stacked usage cards for signed-in providers with live quota.
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
  readonly property color magilla: Style.colorFromHex(Theme.purple, Color.accent)
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  property bool settingsOpen: false
  readonly property var providers: engine ? engine.panelProviders : []
  readonly property double nowMs: engine ? engine.nowMs : Date.now()

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
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(660))

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
            implicitHeight: Math.max(brandMark.height, brandTitle.implicitHeight, brandActions.height)

            Image {
              id: brandMark
              width: Style.space(32)
              height: Style.space(32)
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              source: engine ? engine.magillaUrl() : ""
              sourceSize.width: Style.space(64)
              sourceSize.height: Style.space(64)
              fillMode: Image.PreserveAspectFit
            }

            Text {
              id: brandTitle
              anchors.left: brandMark.right
              anchors.leftMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              text: root.settingsOpen ? "Settings" : "Magilla Usage"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Row {
              id: brandActions
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
            spacing: Style.space(12)

            Text {
              visible: root.providers.length === 0
              width: parent.width
              topPadding: Style.space(12)
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
                width: column.width
                provider: modelData
              }
            }
          }
        }
      }
    }
  }

  component ProviderCard: BorderSurface {
    id: card
    property var provider: null

    readonly property var limits: provider && provider.limits ? provider.limits : []
    readonly property var primary: limits.length > 0 ? limits[0] : null
    readonly property real primaryPct: root.limitPercent(primary)
    readonly property real pace: Model.expectedPace(primary, root.nowMs)
    readonly property bool hot: primaryPct >= 0.9 || (pace >= 0 && primaryPct > pace + 0.02)
    readonly property color barFill: hot ? root.urgent : root.magilla
    readonly property string planName: {
      if (!provider) return ""
      if (provider.tierLabel) return provider.tierLabel
      return provider.providerName || ""
    }

    width: parent ? parent.width : implicitWidth
    implicitHeight: inner.implicitHeight + Style.space(24)
    radius: Math.max(Style.cornerRadius, 10)
    color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.04)
    borderSpec: Border.flat(Qt.rgba(root.magilla.r, root.magilla.g, root.magilla.b, 0.22), 1)

    Column {
      id: inner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.space(14)
      spacing: Style.space(10)

      Item {
        width: parent.width
        implicitHeight: Math.max(planIcon.height, planTitle.implicitHeight, planMeta.implicitHeight)

        Image {
          id: planIcon
          width: Style.font.heading
          height: Style.font.heading
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          source: engine && card.provider ? engine.iconUrl(card.provider.providerId, root.surface) : ""
          sourceSize.width: Style.font.heading * 2
          sourceSize.height: Style.font.heading * 2
          fillMode: Image.PreserveAspectFit
        }

        Column {
          anchors.left: planIcon.right
          anchors.leftMargin: Style.space(10)
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(1)

          Text {
            id: planTitle
            width: parent.width
            text: card.planName
            textFormat: Text.PlainText
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            id: planMeta
            visible: card.provider && card.provider.providerName && card.provider.tierLabel
            width: parent.width
            text: card.provider ? card.provider.providerName : ""
            color: root.dim
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
      }

      Item {
        visible: card.primaryPct >= 0
        width: parent.width
        implicitHeight: Math.max(pctNum.implicitHeight, resetCol.implicitHeight)

        Text {
          id: pctNum
          text: Math.round(card.primaryPct * 100) + "%"
          color: card.hot ? root.urgent : root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.display
          font.bold: true
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
        }

        Column {
          anchors.left: pctNum.right
          anchors.leftMargin: Style.space(10)
          anchors.verticalCenter: pctNum.verticalCenter
          spacing: Style.space(1)

          Text {
            text: {
              var kind = Model.windowKind(card.primary)
              return "of " + kind + " limit"
            }
            color: root.dim
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            visible: text !== ""
            text: Model.remainingLabel(card.primary)
            color: card.hot ? root.urgent : root.magilla
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }

        Column {
          id: resetCol
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(1)

          Text {
            text: Model.formatResetsLabel(card.primary ? card.primary.resetsAt : "")
            color: root.dim
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignRight
            anchors.right: parent.right
          }

          Text {
            visible: card.pace >= 0
            text: card.hot ? "Ahead of pace" : "On pace"
            color: card.hot ? root.urgent : root.dim
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignRight
            anchors.right: parent.right
          }
        }
      }

      PaceMeter {
        visible: card.primaryPct >= 0
        width: parent.width
        value: card.primaryPct
        pace: card.pace
        fill: card.barFill
        weekly: Model.windowKind(card.primary) === "weekly"
      }

      Repeater {
        model: card.limits.length > 1 ? card.limits.slice(1) : []

        Column {
          required property var modelData
          width: inner.width
          spacing: Style.space(5)

          readonly property real pct: root.limitPercent(modelData)

          Item {
            width: parent.width
            implicitHeight: extraLabel.implicitHeight

            Text {
              id: extraLabel
              text: String(modelData.title || modelData.label || "Limit") + " · "
                + (parent.parent.pct >= 0 ? Math.round(parent.parent.pct * 100) + "%" : "—")
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              visible: index === 0
              text: Model.formatResetsLabel(modelData.resetsAt)
              color: root.dim
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          PaceMeter {
            width: parent.width
            value: parent.pct
            pace: Model.expectedPace(modelData, root.nowMs)
            fill: parent.pct >= 0.9 ? root.urgent : Qt.lighter(root.magilla, 1.25)
            weekly: false
          }
        }
      }

      Text {
        visible: card.provider && Number(card.provider.todayTotalTokens) > 0
        width: parent.width
        text: Model.formatTokenCount(card.provider.todayTotalTokens) + " tokens today"
          + (card.provider.todayPrompts > 0 ? " · " + card.provider.todayPrompts + " prompts" : "")
        color: root.dim
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  component PaceMeter: Item {
    id: meter
    property real value: -1
    property real pace: -1
    property color fill: root.magilla
    property bool weekly: false
    implicitHeight: Math.max(Style.space(8), Math.round(Style.spacing.controlHeight * 0.22))

    Rectangle {
      id: meterTrack
      anchors.fill: parent
      radius: height / 2
      color: root.track
      clip: true

      Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        radius: meterTrack.radius
        width: meterTrack.width * root.clamp(meter.value, 0, 1)
        color: meter.fill
        Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
      }

      Repeater {
        model: meter.weekly ? 6 : 0
        Rectangle {
          required property int index
          width: 1
          height: parent.height
          x: parent.width * ((index + 1) / 7)
          color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.18)
        }
      }
    }

    Rectangle {
      visible: meter.pace >= 0
      width: Style.space(2)
      height: parent.height + Style.space(4)
      radius: 1
      x: parent.width * root.clamp(meter.pace, 0, 1) - width / 2
      anchors.verticalCenter: parent.verticalCenter
      color: Color.accent
    }
  }
}

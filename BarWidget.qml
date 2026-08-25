import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Compact signed-in usage chips. Left click opens the panel, right click refreshes.
BarWidget {
  id: root
  moduleName: "io.github.xfurti.magilla-ai-usage"

  readonly property var barProviders: (engine && engine.barProviders) ? engine.barProviders : []
  readonly property string displayStyle: String(setting("displayStyle", "percent"))
  readonly property color fg: bar ? bar.barForeground : Color.foreground
  readonly property color alarm: bar ? bar.urgent : Color.urgent
  readonly property bool alarming: {
    var list = root.barProviders || []
    for (var i = 0; i < list.length; i++) {
      if (list[i] && (list[i].status === "exhausted" || list[i].status === "low"))
        return true
    }
    return false
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function refresh() {
    engine.refresh()
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("engine" in target) target.engine = engine
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Engine {
    id: engine
    settings: root.settings
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "io.github.xfurti.magilla-ai-usage"

    function refresh(): void { root.broadcast("refresh") }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    tooltipText: Model.tooltipSummary(root.barProviders, engine.nowMs)
    active: root.alarming
    horizontalMargin: 8
    fixedWidth: root.vertical ? -1 : Math.max(Style.space(22), chipsRow.implicitWidth + Style.space(14))
    fixedHeight: root.vertical ? Math.max(Style.bar.iconSlot, chipsCol.implicitHeight + Style.space(6)) : -1

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton || buttonCode === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }

    Row {
      id: chipsRow
      visible: !root.vertical
      anchors.centerIn: parent
      spacing: Style.space(10)

      Repeater {
        model: root.barProviders

        Row {
          required property var modelData
          spacing: Style.space(5)
          anchors.verticalCenter: parent.verticalCenter

          Image {
            width: Style.space(13)
            height: Style.space(13)
            anchors.verticalCenter: parent.verticalCenter
            source: engine.iconUrl(modelData.providerId, root.bar ? root.bar.background : Color.background)
            sourceSize.width: Style.space(26)
            sourceSize.height: Style.space(26)
            fillMode: Image.PreserveAspectFit
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: {
              if (root.displayStyle === "remaining") {
                var left = Model.remainingPercent(modelData)
                return left < 0 ? "—" : Model.formatPercent(left)
              }
              var used = Model.usedPercent(modelData)
              return used < 0 ? "—" : Model.formatPercent(used)
            }
            color: (modelData.status === "exhausted" || modelData.status === "low") ? root.alarm : root.fg
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
        }
      }

      Text {
        visible: root.barProviders.length === 0
        anchors.verticalCenter: parent.verticalCenter
        text: "󱚣"
        color: root.fg
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.bar.iconFont
      }
    }

    Column {
      id: chipsCol
      visible: root.vertical
      anchors.centerIn: parent
      spacing: Style.space(2)

      Repeater {
        model: root.barProviders

        Image {
          required property var modelData
          width: Style.space(14)
          height: Style.space(14)
          anchors.horizontalCenter: parent.horizontalCenter
          source: engine.iconUrl(modelData.providerId, root.bar ? root.bar.background : Color.background)
          sourceSize.width: Style.space(28)
          sourceSize.height: Style.space(28)
          fillMode: Image.PreserveAspectFit
        }
      }

      Text {
        visible: root.barProviders.length === 0
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: "󱚣"
        color: root.fg
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.bar.iconFont
      }
    }
  }
}

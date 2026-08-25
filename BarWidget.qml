import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "Theme.js" as Theme

// Compact Magilla chip for the Omarchy bar. Left click opens the panel,
// right click refreshes. Up to three pinned providers sit beside the mark.
BarWidget {
  id: root
  moduleName: "io.github.xfurti.magilla-ai-usage"

  readonly property var barProviders: engine.barProviders
  readonly property string displayStyle: String(setting("displayStyle", "percent"))
  readonly property bool alarming: {
    for (var i = 0; i < barProviders.length; i++) {
      if (barProviders[i].status === "exhausted" || barProviders[i].status === "low")
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
    target: root.moduleName
    function refresh(): string { root.refresh(); return "ok" }
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
    horizontalMargin: 8.5
    fixedWidth: root.vertical ? -1 : Math.max(Style.space(28), chipsRow.implicitWidth + Style.space(16))
    fixedHeight: root.vertical ? Math.max(Style.bar.iconSlot, chipsCol.implicitHeight + Style.space(8)) : -1

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.refresh()
      else if (buttonCode === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }

    Row {
      id: chipsRow
      visible: !root.vertical
      anchors.centerIn: parent
      spacing: Style.space(8)

      Image {
        width: Style.space(16)
        height: Style.space(16)
        anchors.verticalCenter: parent.verticalCenter
        source: engine.magillaUrl()
        sourceSize.width: Style.space(32)
        sourceSize.height: Style.space(32)
        fillMode: Image.PreserveAspectFit
        opacity: engine.refreshing ? 0.55 : 1
        Behavior on opacity { NumberAnimation { duration: 160 } }
      }

      Repeater {
        model: root.barProviders

        Row {
          required property var modelData
          spacing: Style.space(4)
          anchors.verticalCenter: parent.verticalCenter

          Rectangle {
            width: Style.space(6)
            height: Style.space(6)
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.statusHex(modelData.status)
          }

          Image {
            id: providerMark
            width: Style.space(12)
            height: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            source: engine.iconUrl(modelData.providerId)
            sourceSize.width: Style.space(24)
            sourceSize.height: Style.space(24)
            fillMode: Image.PreserveAspectFit
            visible: providerMark.status === Image.Ready
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Model.barLabel(modelData, root.displayStyle)
            color: modelData.status === "exhausted" || modelData.status === "low"
              ? (root.bar ? root.bar.urgent : Color.urgent)
              : (root.bar ? root.bar.barForeground : Color.foreground)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }
        }
      }

      Text {
        visible: root.barProviders.length === 0
        anchors.verticalCenter: parent.verticalCenter
        text: "Magilla"
        color: root.bar ? root.bar.barForeground : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }
    }

    Column {
      id: chipsCol
      visible: root.vertical
      anchors.centerIn: parent
      spacing: Style.space(2)

      Image {
        width: Style.space(16)
        height: Style.space(16)
        anchors.horizontalCenter: parent.horizontalCenter
        source: engine.magillaUrl()
        sourceSize.width: Style.space(32)
        sourceSize.height: Style.space(32)
        fillMode: Image.PreserveAspectFit
      }

      Repeater {
        model: root.barProviders

        Text {
          required property var modelData
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: Model.barLabel(modelData, "compact")
          color: Theme.statusHex(modelData.status)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }
    }
  }
}

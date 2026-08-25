import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "Theme.js" as Theme

// In-panel settings. Persistence goes through the host so shell.json stays
// the single source of truth, same as first-party Omarchy widgets.
Column {
  id: root
  width: parent ? parent.width : implicitWidth
  spacing: Style.space(12)

  property var engine: null
  property var host: null

  readonly property color foreground: host ? host.contentForeground : Color.foreground
  readonly property color dim: host ? host.dim : Qt.darker(foreground, 1.55)
  readonly property string fontFamily: host ? host.contentFontFamily : Style.font.family
  readonly property var settings: host ? host.settings : ({})
  readonly property var allProviders: engine ? engine.providers : []
  readonly property var barSlots: Model.parseBarSlots(settings.barSlots)

  function persist(values) {
    if (host && host.persistSettings) host.persistSettings(values)
  }

  function setProviderEnabled(id, on) {
    var providers = Model.clone(settings.providers, ({}))
    if (!providers[id]) providers[id] = ({})
    providers[id].enabled = on
    var values = { providers: providers }
    if (!on) values.barSlots = Model.joinBarSlots(Model.pinSlots(settings.barSlots, id, false))
    persist(values)
  }

  function setPinned(id, on) {
    persist({ barSlots: Model.joinBarSlots(Model.pinSlots(settings.barSlots, id, on)) })
  }

  function moveSlot(id, delta) {
    var slots = Model.parseBarSlots(settings.barSlots)
    var index = slots.indexOf(id)
    if (index < 0) return
    var next = index + delta
    if (next < 0 || next >= slots.length) return
    var copy = slots.slice()
    copy.splice(index, 1)
    copy.splice(next, 0, id)
    persist({ barSlots: Model.joinBarSlots(copy) })
  }

  PanelSectionHeader {
    width: parent.width
    text: "BAR"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  Text {
    width: parent.width
    text: "Pick up to three providers for the bar. Leave the list empty and Magilla will auto-pick the busiest ones."
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Dropdown {
    width: parent.width
    label: "Display style"
    value: String(root.settings.displayStyle || "percent")
    options: [
      { value: "percent", label: "Percent used" },
      { value: "remaining", label: "Percent remaining" },
      { value: "compact", label: "Compact numbers" }
    ]
    foreground: root.foreground
    fontFamily: root.fontFamily
    onChanged: function(next) { root.persist({ displayStyle: next }) }
  }

  NumberField {
    width: parent.width
    label: "Refresh every (seconds)"
    value: Math.max(30, Number(root.settings.refreshIntervalSec || 300))
    from: 30
    to: 3600
    stepSize: 30
    foreground: root.foreground
    fontFamily: root.fontFamily
    onModified: function(next) { root.persist({ refreshIntervalSec: next }) }
  }

  Toggle {
    width: parent.width
    label: "Show idle tools"
    description: "Keep detected CLIs visible even before they report usage."
    checked: Model.parseOn(root.settings.showIdleProviders, true)
    foreground: root.foreground
    fontFamily: root.fontFamily
    onClicked: root.persist({ showIdleProviders: checked ? "Off" : "On" })
  }

  PanelSeparator { foreground: root.foreground }

  PanelSectionHeader {
    width: parent.width
    text: "PROVIDERS"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  Repeater {
    model: root.allProviders

    BorderSurface {
      required property var modelData
      width: root.width
      implicitHeight: row.implicitHeight + Style.space(16)
      radius: Style.cornerRadius
      color: Style.controlFill(false, false, root.foreground, Color.accent)

      Column {
        id: row
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(12)
        spacing: Style.space(8)

        Row {
          width: parent.width
          spacing: Style.space(8)

          Image {
            width: Style.space(18)
            height: Style.space(18)
            anchors.verticalCenter: parent.verticalCenter
            source: root.engine ? root.engine.iconUrl(modelData.providerId, Color.popups.background) : ""
            sourceSize.width: Style.space(36)
            sourceSize.height: Style.space(36)
            fillMode: Image.PreserveAspectFit
          }

          Column {
            width: parent.width - Style.space(26)
            spacing: Style.space(2)

            Text {
              text: modelData.providerName
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }

            Text {
              text: modelData.detected
                ? (modelData.traces && modelData.traces.length ? modelData.traces.join(" · ") : "Detected")
                : "Not found on this machine"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              width: parent.width
            }
          }
        }

        Row {
          spacing: Style.space(8)

          Button {
            text: modelData.enabled ? "Enabled" : "Disabled"
            selected: modelData.enabled
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            onClicked: root.setProviderEnabled(modelData.providerId, !modelData.enabled)
          }

          Button {
            text: root.barSlots.indexOf(modelData.providerId) >= 0 ? "On bar" : "Pin to bar"
            selected: root.barSlots.indexOf(modelData.providerId) >= 0
            bordered: true
            enabled: modelData.enabled && modelData.detected
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            onClicked: root.setPinned(modelData.providerId, root.barSlots.indexOf(modelData.providerId) < 0)
          }

          PanelActionButton {
            visible: root.barSlots.indexOf(modelData.providerId) >= 0
            iconText: "󰅃"
            tooltipText: "Move up"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.moveSlot(modelData.providerId, -1)
          }

          PanelActionButton {
            visible: root.barSlots.indexOf(modelData.providerId) >= 0
            iconText: "󰅀"
            tooltipText: "Move down"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.moveSlot(modelData.providerId, 1)
          }
        }
      }
    }
  }
}

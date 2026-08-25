import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

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
  readonly property var barSlots: Model.parseBarSlots(settings.barSlots)

  readonly property var liveProviders: {
    var list = []
    var all = engine ? engine.providers : []
    for (var i = 0; i < all.length; i++) if (all[i].hasLiveData) list.push(all[i])
    return list
  }

  readonly property var pendingProviders: {
    var list = []
    var all = engine ? engine.providers : []
    for (var i = 0; i < all.length; i++)
      if (!all[i].hasLiveData && all[i].installed) list.push(all[i])
    return list
  }

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

  PanelSectionHeader {
    width: parent.width
    text: "BAR"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  Dropdown {
    width: parent.width
    label: "Label"
    value: String(root.settings.displayStyle || "percent")
    options: [
      { value: "percent", label: "Percent used" },
      { value: "remaining", label: "Percent remaining" },
      { value: "compact", label: "Percent only" }
    ]
    foreground: root.foreground
    fontFamily: root.fontFamily
    onChanged: function(next) { root.persist({ displayStyle: next }) }
  }

  NumberField {
    width: parent.width
    label: "Refresh (seconds)"
    value: Math.max(30, Number(root.settings.refreshIntervalSec || 300))
    from: 30
    to: 3600
    stepSize: 30
    foreground: root.foreground
    fontFamily: root.fontFamily
    onModified: function(next) { root.persist({ refreshIntervalSec: next }) }
  }

  PanelSeparator { foreground: root.foreground }

  PanelSectionHeader {
    width: parent.width
    text: "ACTIVE"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  Text {
    visible: root.liveProviders.length === 0
    width: parent.width
    text: "No signed-in usage on this machine."
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Repeater {
    model: root.liveProviders
    ProviderRow {
      required property var modelData
      width: root.width
      provider: modelData
      allowPin: true
    }
  }

  PanelSeparator {
    visible: root.pendingProviders.length > 0
    foreground: root.foreground
  }

  PanelSectionHeader {
    visible: root.pendingProviders.length > 0
    width: parent.width
    text: "INSTALLED, NOT SIGNED IN"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  Text {
    visible: root.pendingProviders.length > 0
    width: parent.width
    text: "These stay off the main view until you sign in and usage data is available."
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Repeater {
    model: root.pendingProviders
    ProviderRow {
      required property var modelData
      width: root.width
      provider: modelData
      allowPin: false
    }
  }

  component ProviderRow: Item {
    id: row
    property var provider: null
    property bool allowPin: true
    readonly property bool showPin: allowPin && provider && provider.enabled && provider.hasLiveData
    implicitHeight: Style.space(44)

    Image {
      id: mark
      width: Style.space(16)
      height: Style.space(16)
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      source: root.engine && row.provider ? root.engine.iconUrl(row.provider.providerId, Color.popups.background) : ""
      sourceSize.width: Style.space(32)
      sourceSize.height: Style.space(32)
      fillMode: Image.PreserveAspectFit
    }

    Column {
      anchors.left: mark.right
      anchors.leftMargin: Style.space(10)
      anchors.right: row.showPin ? pinBtn.left : enabledSwitch.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(1)

      Text {
        width: parent.width
        text: row.provider ? row.provider.providerName : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        visible: row.provider && !row.provider.hasLiveData
        width: parent.width
        text: row.provider && row.provider.authHelpText ? row.provider.authHelpText : "Sign in to see usage"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    ToggleSwitch {
      id: enabledSwitch
      visible: row.allowPin
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      checked: !!(row.provider && row.provider.enabled)
      onToggled: if (row.provider) root.setProviderEnabled(row.provider.providerId, !row.provider.enabled)
    }

    PanelActionButton {
      id: pinBtn
      visible: row.showPin
      anchors.right: enabledSwitch.visible ? enabledSwitch.left : parent.right
      anchors.rightMargin: enabledSwitch.visible ? Style.space(4) : 0
      anchors.verticalCenter: parent.verticalCenter
      iconText: root.barSlots.indexOf(row.provider ? row.provider.providerId : "") >= 0 ? "󰐃" : "󰤱"
      tooltipText: root.barSlots.indexOf(row.provider ? row.provider.providerId : "") >= 0 ? "Unpin from bar" : "Pin to bar"
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: if (row.provider) root.setPinned(row.provider.providerId, root.barSlots.indexOf(row.provider.providerId) < 0)
    }
  }
}

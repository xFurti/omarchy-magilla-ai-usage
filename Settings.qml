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

  readonly property var signedIn: {
    var list = []
    var all = engine ? engine.providers : []
    for (var i = 0; i < all.length; i++) if (all[i].authenticated) list.push(all[i])
    return list
  }

  readonly property var otherInstalls: {
    var list = []
    var all = engine ? engine.providers : []
    for (var i = 0; i < all.length; i++)
      if (!all[i].authenticated && all[i].installed) list.push(all[i])
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
    text: "DISPLAY"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  Dropdown {
    width: parent.width
    label: "Bar label"
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
    label: "Refresh interval (seconds)"
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
    text: "SIGNED IN"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  Text {
    visible: root.signedIn.length === 0
    width: parent.width
    text: "Nothing signed in on this machine yet."
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  Repeater {
    model: root.signedIn
    ProviderRow {
      required property var modelData
      width: root.width
      provider: modelData
      allowPin: true
    }
  }

  PanelSeparator {
    visible: root.otherInstalls.length > 0
    foreground: root.foreground
  }

  PanelSectionHeader {
    visible: root.otherInstalls.length > 0
    width: parent.width
    text: "INSTALLED, NOT SIGNED IN"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  Repeater {
    model: root.otherInstalls
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
    readonly property bool showPin: allowPin && provider && provider.enabled
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

    Text {
      anchors.left: mark.right
      anchors.leftMargin: Style.space(10)
      anchors.right: row.showPin ? pinBtn.left : enabledSwitch.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: row.provider ? row.provider.providerName : ""
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }

    ToggleSwitch {
      id: enabledSwitch
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      checked: !!(row.provider && row.provider.enabled)
      onToggled: if (row.provider) root.setProviderEnabled(row.provider.providerId, !row.provider.enabled)
    }

    PanelActionButton {
      id: pinBtn
      visible: row.allowPin && row.provider && row.provider.enabled
      anchors.right: enabledSwitch.left
      anchors.rightMargin: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      iconText: root.barSlots.indexOf(row.provider ? row.provider.providerId : "") >= 0 ? "󰐃" : "󰤱"
      tooltipText: root.barSlots.indexOf(row.provider ? row.provider.providerId : "") >= 0 ? "Unpin from bar" : "Pin to bar"
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: if (row.provider) root.setPinned(row.provider.providerId, root.barSlots.indexOf(row.provider.providerId) < 0)
    }
  }
}

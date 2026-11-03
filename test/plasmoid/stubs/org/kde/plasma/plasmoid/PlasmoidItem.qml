// SPDX-License-Identifier: GPL-3.0-only
// Test stand-in for the PlasmoidItem plasmashell provides, so qml6 can run the
// widget's main.qml outside a desktop: the properties main.qml uses, with both
// representations always shown. Everything else main.qml touches (the
// executable data engine, Kirigami, the Plasma components) is the real thing.
import QtQuick

Item {
    id: item

    property Component compactRepresentation
    property Component fullRepresentation
    readonly property Item compactRepresentationItem: compact.item
    readonly property Item fullRepresentationItem: full.item
    property bool expanded: false
    property string toolTipMainText
    property string toolTipSubText
    property int toolTipTextFormat

    Loader {
        id: compact
        width: 32
        height: 32
        sourceComponent: item.compactRepresentation
    }

    Loader {
        id: full
        anchors.fill: parent
        sourceComponent: item.fullRepresentation
    }
}

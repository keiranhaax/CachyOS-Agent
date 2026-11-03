// SPDX-License-Identifier: GPL-3.0-only
// Test stand-in for the Plasmoid object plasmashell attaches to a widget: only
// the configuration main.qml reads, with the defaults of config/main.xml, and
// the status it sets (a PlasmaCore.Types.ItemStatus).
pragma Singleton
import QtQuick

QtObject {
    property int status
    property var configuration: ({
        refreshIntervalSec: 900
    })
}

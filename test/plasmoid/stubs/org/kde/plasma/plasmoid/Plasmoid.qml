// SPDX-License-Identifier: GPL-3.0-only
// Test stand-in for the Plasmoid object plasmashell attaches to a widget: only
// the configuration main.qml reads, with the defaults of config/main.xml.
pragma Singleton
import QtQuick

QtObject {
    property var configuration: ({
        refreshIntervalSec: 900
    })
}

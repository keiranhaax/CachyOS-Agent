// SPDX-License-Identifier: GPL-3.0-only
// Loads the widget's settings page and the model that offers it, sets the page's
// cfg_refreshIntervalSec the way plasmashell does, and prints what the page's
// spin box and the model say, as JSON.
//   qml6 config.qml -- <configGeneral.qml> <config.qml>
// test/cases/80-plasmoid.sh reads the line qml6 logs for it.
import QtQuick

Item {
    id: harness

    width: 600
    height: 400

    readonly property var args: Qt.application.arguments.slice(Qt.application.arguments.indexOf("--") + 1)

    Loader {
        id: page
        anchors.fill: parent
        source: "file://" + harness.args[0]
    }

    Loader {
        id: categories
        source: "file://" + harness.args[1]
    }

    function find(item, matches) {
        if (matches(item))
            return item;
        for (const child of item.children) {
            const found = find(child, matches);
            if (found)
                return found;
        }
        return null;
    }

    Timer {
        interval: 300
        running: true
        onTriggered: {
            try {
                page.item.cfg_refreshIntervalSec = 120;
                const spin = harness.find(page.item, item => typeof item.stepSize === "number" && typeof item.from === "number");
                console.log("RESULT " + JSON.stringify({
                    loaded: page.status === Loader.Ready && categories.status === Loader.Ready,
                    spin: { value: spin.value, from: spin.from, to: spin.to },
                    categories: Array.from({ length: categories.item.count }, (unused, row) => categories.item.get(row))
                }));
            } finally {
                Qt.quit();
            }
        }
    }
}

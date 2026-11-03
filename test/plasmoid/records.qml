// SPDX-License-Identifier: GPL-3.0-only
// Calls one function of the widget's records.js and prints its result as JSON.
//   QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen qml6 records.qml -- '["load", 0, "[]", "", 0]'
// The argument is a JSON array: the function's name, then its arguments.
// test/cases/80-plasmoid.sh reads the line qml6 logs for it.
import QtQuick
import "../../plasmoid/org.cachyos.agent/contents/code/records.js" as Records

Item {
    // A call that throws logs why and ends the run with no result line.
    Component.onCompleted: {
        try {
            const call = JSON.parse(Qt.application.arguments[Qt.application.arguments.length - 1]);
            console.log("RESULT " + JSON.stringify(Records[call[0]].apply(null, call.slice(1))));
        } finally {
            Qt.quit();
        }
    }
}

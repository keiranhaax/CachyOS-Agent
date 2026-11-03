// SPDX-License-Identifier: GPL-3.0-only
// Runs the widget's main.qml against the stubs in stubs/, with the real data
// engine running a stubbed cachyos-agent, and prints what it shows as JSON.
//   qml6 -I stubs app.qml -- <main.qml> <action> <expected>
// action is "dump", "compact" (click the panel icon), or the text of a button to
// click. After an action the page is printed once its agents mention <expected>
// (or after 10 seconds, or a second when <expected> is empty); "during" is how
// the widget looked right after the action. test/cases/80-plasmoid.sh reads the
// line qml6 logs for it.
import QtQuick

Item {
    id: harness

    width: 800
    height: 6000

    readonly property var args: Qt.application.arguments.slice(Qt.application.arguments.indexOf("--") + 1)
    readonly property Item app: loader.item
    property int waited: 0
    property bool acted: false
    property var during: null

    Loader {
        id: loader
        anchors.fill: parent
        source: "file://" + harness.args[0]
    }

    // Visits every visible item below `item`, not entering a button: its own
    // label is Plasma's, not the widget's.
    function walk(item, visit) {
        if (!item.visible)
            return;
        visit(item);
        if (typeof item.clicked === "function")
            return;
        for (const child of item.children)
            walk(child, visit);
    }

    function state() {
        const page = { texts: [], notPlain: [], bars: [], buttons: [] };
        walk(app.fullRepresentationItem, item => {
            if (typeof item.clicked === "function" && typeof item.text === "string")
                page.buttons.push({ text: item.text, enabled: item.enabled });
            else if (typeof item.textFormat === "number" && typeof item.text === "string") {
                page.texts.push(item.text);
                if (item.textFormat !== Text.PlainText)
                    page.notPlain.push(item.text);
            } else if (typeof item.indeterminate === "boolean" && typeof item.value === "number")
                page.bars.push(item.value);
        });
        return {
            loaded: app.loaded,
            problem: app.problem,
            refreshing: app.refreshing,
            expanded: app.expanded,
            tooltip: app.toolTipSubText,
            compactIcon: app.compactRepresentationItem.children[0].source,
            agents: app.agents,
            page: page
        };
    }

    function act(action) {
        if (action === "compact") {
            app.compactRepresentationItem.clicked(null);
        } else {
            let button = null;
            walk(app.fullRepresentationItem, item => {
                if (typeof item.clicked === "function" && item.text === action)
                    button = item;
            });
            button.clicked();
        }
        const now = state();
        during = { refreshing: now.refreshing, expanded: now.expanded, buttons: now.page.buttons };
    }

    function finish() {
        console.log("RESULT " + JSON.stringify(Object.assign(state(), { during: during })));
        Qt.quit();
    }

    // Waits for the first read, does the action if asked to, then waits for the
    // page to settle: a second at least, so a command the action only starts has
    // run before the harness quits.
    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            harness.waited += interval;
            if (!harness.app || !harness.app.loaded)
                return;
            try {
                if (harness.args[1] === "dump") {
                    harness.finish();
                } else if (!harness.acted) {
                    harness.acted = true;
                    harness.act(harness.args[1]);
                    harness.waited = 0;
                } else if (harness.waited >= 10000 || (harness.waited >= 1000 && JSON.stringify(harness.app.agents).includes(harness.args[2]))) {
                    harness.finish();
                }
            } catch (error) {
                // Log why and end the run with no result line.
                console.warn("harness: " + error);
                Qt.quit();
            }
        }
    }
}

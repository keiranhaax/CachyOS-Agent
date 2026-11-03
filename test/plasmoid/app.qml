// SPDX-License-Identifier: GPL-3.0-only
// Runs the widget's main.qml against the stubs in stubs/, with the real data
// engine running a stubbed cachyos-agent, and prints what it shows as JSON.
//   qml6 -I stubs app.qml -- <main.qml> <actions> <expected>
// actions is "dump", or one or more of "compact" (click the panel icon),
// "reload" (what the widget's timer does), "later" (the clock moves an hour on
// with no new read, as it does between the timer's runs) and the text of a button to click,
// joined by "+" and done a second apart. After the last action the page is
// printed once its agents mention <expected> (or after 10 seconds, or a second
// when <expected> is empty); "during" is how the widget looked right after the
// first action and "seen" how it looked just before each action.
// test/cases/80-plasmoid.sh reads the line qml6 logs for it.
import QtQuick
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

Item {
    id: harness

    width: 800
    height: 6000

    readonly property var args: Qt.application.arguments.slice(Qt.application.arguments.indexOf("--") + 1)
    readonly property Item app: loader.item
    readonly property var actions: String(args[1]).split("+")
    property int waited: 0
    property int done: 0
    property var during: null
    property var seen: []

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
            attention: Plasmoid.status === PlasmaCore.Types.NeedsAttentionStatus,
            tooltip: app.toolTipSubText,
            compactIcon: app.compactRepresentationItem.children[0].source,
            agents: app.agents,
            page: page
        };
    }

    function act(action) {
        if (action === "compact") {
            app.compactRepresentationItem.clicked(null);
        } else if (action === "reload") {
            app.load();
        } else if (action === "later") {
            app.now += 3600 * 1000;
        } else {
            let button = null;
            walk(app.fullRepresentationItem, item => {
                if (typeof item.clicked === "function" && item.text === action)
                    button = item;
            });
            button.clicked();
        }
        const now = state();
        if (during === null)
            during = { refreshing: now.refreshing, expanded: now.expanded, buttons: now.page.buttons };
    }

    function finish() {
        console.log("RESULT " + JSON.stringify(Object.assign(state(), { during: during, seen: seen })));
        Qt.quit();
    }

    // Waits for the first read, does the actions if asked to, then waits for the
    // page to settle: a second at least, so a command the last action only
    // starts has run before the harness quits.
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
                } else if (harness.done < harness.actions.length) {
                    if (harness.done === 0 || harness.waited >= 1000) {
                        harness.seen.push(harness.state());
                        harness.act(harness.actions[harness.done]);
                        harness.done++;
                        harness.waited = 0;
                    }
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

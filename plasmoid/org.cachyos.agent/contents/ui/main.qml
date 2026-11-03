// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Omarchy shell/plugins/agents/Main.qml and Panel.qml (MIT, Copyright (c) David Heinemeier Hansson); see THIRD_PARTY_NOTICES.md
pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.plasmoid
import "../code/records.js" as Records

// Agent usage in the panel. The widget only displays: `cachyos-agent usage
// update` (a systemd timer, or the Refresh button) writes the records, and this
// reads them back with `cachyos-agent usage --json`.
PlasmoidItem {
    id: root

    // The last read, as code/records.js shapes it. Nothing is drawn from
    // `agents` before `loaded`.
    property var agents: []
    property string loadError: ""
    // Why the last Refresh failed. It is shown beside the records read right
    // after it and goes with the next read, so it never stays above numbers
    // the timer has since brought up to date.
    property string updateError: ""
    // The failure of an update that has finished, until the read after it reports it.
    property string failedUpdate: ""
    property bool loaded: false
    property bool refreshing: false
    // The clock the reset countdowns read: it moves every minute and with every read.
    property double now: Date.now()

    readonly property string problem: loadError || updateError

    // The executable engine runs its source name through sh -c and runs a given
    // name once at a time, so these are fixed strings and never built from data.
    readonly property string loadCommand: "cachyos-agent usage --json"
    readonly property string updateCommand: "cachyos-agent usage update"
    // systemd-run puts the agent's terminal in a scope of its own, so restarting
    // plasmashell does not end a session started here. The trailing & returns at
    // once, which lets a second click start a second agent, and the redirects
    // keep the terminal from holding the engine's pipes open. Nothing here can
    // show what the launcher printed, so a failure is the launcher's to report.
    readonly property string launchCommand: "systemd-run --user --scope --quiet -- cachyos-agent launch >/dev/null 2>&1 &"

    toolTipMainText: "CachyOS Agents"
    toolTipSubText: Records.summary(agents)
    toolTipTextFormat: Text.PlainText

    function load() {
        runner.connectSource(loadCommand);
    }

    // Collects fresh records, then reads them. A failed update still reads: the
    // collectors that worked have written theirs.
    function refresh() {
        if (refreshing)
            return;
        refreshing = true;
        updateError = "";
        runner.connectSource(updateCommand);
    }

    function launch() {
        runner.connectSource(launchCommand);
    }

    function finished(source, exitCode, stdout, stderr) {
        if (source === loadCommand) {
            const result = Records.load(exitCode, stdout, stderr, Date.now());
            agents = result.agents;
            loadError = result.error;
            updateError = failedUpdate;
            failedUpdate = "";
            now = Date.now();
            loaded = true;
        } else if (source === updateCommand) {
            refreshing = false;
            failedUpdate = exitCode === 0 ? "" : Records.failure(updateCommand, exitCode, stderr);
            load();
        }
    }

    Plasma5Support.DataSource {
        id: runner
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            runner.disconnectSource(source);
            root.finished(source, data["exit code"], data["stdout"], data["stderr"]);
        }
    }

    Timer {
        // The keys of Plasmoid.configuration come from config/main.xml, which qmllint cannot see.
        interval: Math.max(30, Plasmoid.configuration.refreshIntervalSec) * 1000 // qmllint disable missing-property
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.load()
    }

    Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: root.now = Date.now()
    }

    // Show what is true now, not what the last timer tick found.
    onExpandedChanged: {
        if (expanded)
            load();
    }

    compactRepresentation: MouseArea {
        onClicked: root.expanded = !root.expanded

        Kirigami.Icon {
            anchors.fill: parent
            source: "utilities-terminal"
        }
    }

    fullRepresentation: FullRepresentation {
        agents: root.agents
        problem: root.problem
        loaded: root.loaded
        refreshing: root.refreshing
        now: root.now
        onLaunchRequested: root.launch()
        onRefreshRequested: root.refresh()
    }
}

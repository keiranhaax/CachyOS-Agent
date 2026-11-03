// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Omarchy shell/plugins/agents/Panel.qml (MIT, Copyright (c) David Heinemeier Hansson); see THIRD_PARTY_NOTICES.md
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras

// The popup: a header with the two buttons, then one section per agent.
PlasmaExtras.Representation {
    id: full

    property var agents: []
    property string problem: ""
    property bool loaded: false
    property bool refreshing: false
    property double now: 0

    signal launchRequested
    signal refreshRequested

    Layout.minimumWidth: Kirigami.Units.gridUnit * 18
    Layout.minimumHeight: Kirigami.Units.gridUnit * 14
    Layout.preferredWidth: Kirigami.Units.gridUnit * 22
    Layout.preferredHeight: Kirigami.Units.gridUnit * 28

    header: PlasmaExtras.PlasmoidHeading {
        RowLayout {
            anchors.fill: parent

            PlasmaExtras.Heading {
                Layout.fillWidth: true
                level: 3
                text: "CachyOS Agents"
                textFormat: Text.PlainText
                elide: Text.ElideRight
            }

            PlasmaComponents3.Button {
                text: "Launch agent"
                icon.name: "utilities-terminal"
                onClicked: full.launchRequested()
            }

            PlasmaComponents3.Button {
                text: "Refresh"
                icon.name: "view-refresh"
                enabled: !full.refreshing
                onClicked: full.refreshRequested()
            }
        }
    }

    contentItem: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.smallSpacing
            visible: full.problem !== ""
            text: full.problem
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Kirigami.Theme.negativeTextColor
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: full.agents.length === 0 && full.problem === ""
            text: full.loaded ? "No agent usage yet. Press Refresh to collect it." : "Loading usage…"
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            opacity: 0.7
        }

        PlasmaComponents3.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: full.agents.length > 0
            contentWidth: availableWidth

            // Without this the scrollbar appearing narrows the list, which hides it again.
            QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

            contentItem: ListView {
                clip: true
                model: full.agents
                spacing: Kirigami.Units.largeSpacing
                leftMargin: Kirigami.Units.smallSpacing
                rightMargin: Kirigami.Units.smallSpacing
                topMargin: Kirigami.Units.smallSpacing

                delegate: AgentSection {
                    width: ListView.view.width - ListView.view.leftMargin - ListView.view.rightMargin
                    now: full.now
                }
            }
        }
    }
}

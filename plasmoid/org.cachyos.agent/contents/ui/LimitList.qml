// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Omarchy shell/plugins/agents/Panel.qml (MIT, Copyright (c) David Heinemeier Hansson); see THIRD_PARTY_NOTICES.md
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "../code/records.js" as Records

// What is wrong with an agent's numbers, then each limit window as a meter with
// its percent and when it resets. An agent and each of its accounts use one.
ColumnLayout {
    id: list

    property var notes: []
    property var limits: []
    property double now: 0

    spacing: Kirigami.Units.smallSpacing

    Repeater {
        model: list.notes

        PlasmaComponents3.Label {
            required property string modelData

            Layout.fillWidth: true
            text: modelData
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Kirigami.Theme.neutralTextColor
        }
    }

    Repeater {
        model: list.limits

        ColumnLayout {
            id: row

            required property var modelData
            readonly property string reset: Records.resetText(modelData.resetMs, list.now)

            Layout.fillWidth: true
            spacing: 0

            RowLayout {
                Layout.fillWidth: true

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: row.modelData.title
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                }

                PlasmaComponents3.Label {
                    text: row.modelData.percentText + (row.reset !== "" ? "  ·  " + row.reset : "")
                    textFormat: Text.PlainText
                    color: row.modelData.high ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                }
            }

            PlasmaComponents3.ProgressBar {
                Layout.fillWidth: true
                from: 0
                to: 1
                value: row.modelData.fraction
            }
        }
    }
}

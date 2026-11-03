// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Omarchy shell/plugins/agents/Panel.qml (MIT, Copyright (c) David Heinemeier Hansson); see THIRD_PARTY_NOTICES.md
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras

// One agent: its name and plan, then its limits or prepaid balance, its
// tokens, and each of its accounts when it has several. Several accounts
// take the place of the agent's own limits: the record's limits describe the
// active account, which is listed with the others.
ColumnLayout {
    id: section

    required property var modelData
    property double now: 0

    readonly property var agent: modelData

    spacing: Kirigami.Units.smallSpacing

    RowLayout {
        Layout.fillWidth: true

        PlasmaExtras.Heading {
            Layout.fillWidth: true
            level: 4
            text: section.agent.name
            textFormat: Text.PlainText
            elide: Text.ElideRight
        }

        PlasmaComponents3.Label {
            visible: text !== ""
            text: section.agent.plan
            textFormat: Text.PlainText
            opacity: 0.7
        }
    }

    LimitList {
        Layout.fillWidth: true
        visible: !section.agent.multi
        notes: section.agent.notes
        limits: section.agent.limits
        now: section.now
    }

    Repeater {
        model: section.agent.balance ? [section.agent.balance] : []

        ColumnLayout {
            id: balance

            required property var modelData

            Layout.fillWidth: true
            spacing: 0

            RowLayout {
                Layout.fillWidth: true

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: "Balance"
                    textFormat: Text.PlainText
                }

                PlasmaComponents3.Label {
                    text: balance.modelData.remainingText
                    textFormat: Text.PlainText
                    color: balance.modelData.low ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                }
            }

            PlasmaComponents3.ProgressBar {
                Layout.fillWidth: true
                visible: balance.modelData.fraction >= 0
                from: 0
                to: 1
                value: Math.max(balance.modelData.fraction, 0)
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                visible: text !== ""
                text: balance.modelData.detailText
                textFormat: Text.PlainText
                opacity: 0.7
            }
        }
    }

    Repeater {
        model: section.agent.multi ? section.agent.accounts : []

        ColumnLayout {
            id: account

            required property var modelData

            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.largeSpacing

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: [account.modelData.name, account.modelData.plan, account.modelData.active ? "active" : ""].filter(part => part !== "").join(" · ")
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font.bold: account.modelData.active
            }

            LimitList {
                Layout.fillWidth: true
                notes: account.modelData.notes
                limits: account.modelData.limits
                now: section.now
            }
        }
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        visible: text !== ""
        text: section.agent.tokensText
        textFormat: Text.PlainText
        opacity: 0.7
    }

    Kirigami.Separator {
        Layout.fillWidth: true
    }
}

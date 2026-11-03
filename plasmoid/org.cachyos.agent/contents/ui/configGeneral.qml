// SPDX-License-Identifier: GPL-3.0-only
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    property alias cfg_refreshIntervalSec: interval.value

    Kirigami.FormLayout {
        QQC2.SpinBox {
            id: interval

            Kirigami.FormData.label: "Refresh interval (seconds):"
            from: 30
            to: 3600
            stepSize: 30
        }
    }
}

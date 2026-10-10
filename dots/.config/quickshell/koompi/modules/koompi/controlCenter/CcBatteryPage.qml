import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    spacing: Appearance.spacing.small

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: charge.implicitHeight + Appearance.spacing.large * 2
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1

        ColumnLayout {
            id: charge
            anchors {
                fill: parent
                margins: Appearance.spacing.large
            }
            spacing: Appearance.spacing.small
            StyledText {
                font.pixelSize: Appearance.font.pixelSize.huge
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
                text: `${Math.round(Battery.percentage * 100)}%`
            }
            StyledText {
                color: Appearance.colors.colSubtext
                text: Battery.isCharging ? Translation.tr("Charging") : Battery.isPluggedIn ? Translation.tr("Plugged in") : Translation.tr("On battery")
            }
            StyledProgressBar {
                Layout.fillWidth: true
                value: Battery.percentage
            }
        }
    }

    CcRow {
        objectName: "cc-chargeLimit"
        visible: ChargeLimit.supported
        icon: "battery_saver"
        title: Translation.tr("Limit charging to %1%").arg(ChargeLimit.endThreshold)
        detail: Translation.tr("Resumes below %1%").arg(ChargeLimit.startThreshold)
        toggled: ChargeLimit.enabled
        onActivated: ChargeLimit.setEnabled(!ChargeLimit.enabled)
    }

    CcLinkRow {
        buttonText: Translation.tr("More power settings")
        page: "power"
    }

    Item {
        Layout.fillHeight: true
    }
}

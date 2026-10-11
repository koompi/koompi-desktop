import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root
    readonly property bool isCharging: Battery.isCharging
    readonly property real percentage: Battery.percentage
    readonly property bool isLow: percentage <= Config.options.battery.low / 100
    property color color: Appearance.colors.colOnLayer0

    implicitWidth: row.implicitWidth
    implicitHeight: Appearance.sizes.barHeight

    hoverEnabled: !Config.options.bar.tooltips.clickToShow
    cursorShape: Qt.PointingHandCursor
    // hover shows the popup; a click opens the battery page (with click-to-show tooltips, the click is the popup's)
    onClicked: if (!Config.options.bar.tooltips.clickToShow) GlobalStates.toggleSidebarRightOn("battery")

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 2

        MaterialSymbol {
            text: root.isCharging ? "battery_charging_full" : Icons.getBatteryIcon(root.percentage * 100)
            fill: 1
            iconSize: Appearance.font.pixelSize.larger
            color: (root.isLow && !root.isCharging) ? Appearance.m3colors.m3error : root.color
        }
        StyledText {
            objectName: "batteryPercent"
            font.pixelSize: Appearance.font.pixelSize.small
            color: (root.isLow && !root.isCharging) ? Appearance.m3colors.m3error : root.color
            text: Math.round(root.percentage * 100) + "%"
        }
    }

    BatteryPopup {
        id: batteryPopup
        hoverTarget: root
    }
}

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import qs.modules.koompi.bar as Bar

MouseArea {
    id: root
    readonly property bool isCharging: Battery.isCharging
    readonly property real percentage: Battery.percentage
    readonly property bool isLow: percentage <= Config.options.battery.low / 100
    property color color: Appearance.colors.colOnLayer0

    implicitHeight: column.implicitHeight
    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    ColumnLayout {
        id: column
        anchors.centerIn: parent
        spacing: -2

        MaterialSymbol {
            Layout.alignment: Qt.AlignHCenter
            text: root.isCharging ? "battery_charging_full" : Icons.getBatteryIcon(root.percentage * 100)
            fill: 1
            iconSize: Appearance.font.pixelSize.larger
            color: (root.isLow && !root.isCharging) ? Appearance.m3colors.m3error : root.color
        }
        StyledText {
            objectName: "batteryPercent"
            Layout.alignment: Qt.AlignHCenter
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: (root.isLow && !root.isCharging) ? Appearance.m3colors.m3error : root.color
            text: Math.round(root.percentage * 100)
        }
    }

    Bar.BatteryPopup {
        id: batteryPopup
        hoverTarget: root
    }
}

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick

// A desk's outline and number, over its tiles so a window that fills the desk hides neither.
Rectangle {
    id: root
    required property int deskId
    property bool isNew: false
    property bool isActive: false
    property bool selected: false

    color: "transparent"
    radius: Appearance.rounding.normal
    border.width: selected ? 3 : (isActive || isNew ? 2 : 1)
    border.color: selected ? Appearance.colors.colPrimary : (isActive ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.45) : ColorUtils.transparentize(Appearance.colors.colOutline, isNew ? 0.4 : 0.7))

    Rectangle {
        anchors {
            top: parent.top
            left: parent.left
            margins: 8
        }
        width: Math.max(height, label.implicitWidth + 14)
        height: label.implicitHeight + 6
        radius: height / 2
        color: root.selected ? Appearance.colors.colPrimary : Appearance.colors.colBackgroundSurfaceContainer
        StyledText {
            id: label
            anchors.centerIn: parent
            text: root.deskId
            font.weight: Font.DemiBold
            color: root.selected ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1
        }
    }
}

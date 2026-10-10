import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick

// One desk of the overview: its number, and the room its tiles sit in.
Rectangle {
    id: root
    required property int deskId
    property bool isNew: false
    property bool isActive: false
    property bool selected: false
    property bool dropHover: false

    signal activated
    signal dragEntered
    signal dragExited

    objectName: "overviewDesk"
    radius: Appearance.rounding.normal
    color: dropHover ? ColorUtils.mix(Appearance.colors.colSurfaceContainerLow, Appearance.colors.colPrimary, 0.82) : (isNew ? "transparent" : Appearance.colors.colSurfaceContainerLow)
    border.width: selected ? 3 : (isActive || isNew ? 2 : 1)
    border.color: selected ? Appearance.colors.colPrimary : (isActive ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.45) : ColorUtils.transparentize(Appearance.colors.colOutline, isNew ? 0.4 : 0.75))

    StyledText {
        visible: root.isNew
        anchors.centerIn: parent
        text: "+"
        font.pixelSize: Math.min(root.height * 0.4, 96)
        color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.55)
    }

    Rectangle {
        anchors {
            top: parent.top
            left: parent.left
            margins: 8
        }
        width: Math.max(height, label.implicitWidth + 14)
        height: label.implicitHeight + 6
        radius: height / 2
        color: root.selected ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colLayer1, 0.15)
        StyledText {
            id: label
            anchors.centerIn: parent
            text: root.deskId
            font.weight: Font.DemiBold
            color: root.selected ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1
        }
    }

    DropArea {
        anchors.fill: parent
        onEntered: root.dragEntered()
        onExited: root.dragExited()
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.activated()
    }
}

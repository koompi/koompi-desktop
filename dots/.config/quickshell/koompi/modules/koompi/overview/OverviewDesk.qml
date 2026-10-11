import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick

// One desk of the overview: the room its tiles sit in, and what a click or a drop on it does.
// The outline and number are OverviewDeskFrame, drawn over the tiles.
Rectangle {
    id: root
    required property int deskId
    property bool isNew: false
    property bool selected: false
    property bool dropHover: false

    signal activated
    signal dragEntered
    signal dragExited

    objectName: "overviewDesk"
    radius: Appearance.rounding.normal
    color: dropHover ? ColorUtils.mix(Appearance.colors.colSurfaceContainerLow, Appearance.colors.colPrimary, 0.82) : (isNew ? "transparent" : Appearance.colors.colSurfaceContainerLow)

    StyledText {
        visible: root.isNew
        anchors.centerIn: parent
        text: "+"
        font.pixelSize: Math.min(root.height * 0.4, 96)
        color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.55)
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

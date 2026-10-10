pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import Quickshell.Hyprland
import Quickshell.Wayland
import "OverviewGrid.js" as Grid

// A window drawn where it sits on its desk, at the desk's scale.
Item {
    id: root
    required property var toplevel
    required property var windowData
    // the desk's cell in the grid, how much smaller a window is drawn than it is,
    // and the screen point the desk's top left stands for
    property rect cell
    property real deskScale: 1
    property real originX: 0
    property real originY: 0
    property real liveMinWidth: 320
    property bool selected: false
    property bool showTitle: false

    readonly property bool hovered: dragArea.containsMouse
    readonly property bool live: Grid.isLive(width, liveMinWidth)
    readonly property string address: windowData?.address ?? ""
    readonly property real offX: Math.max(0, ((windowData?.at[0] ?? 0) - originX) * deskScale)
    readonly property real offY: Math.max(0, ((windowData?.at[1] ?? 0) - originY) * deskScale)

    signal released(string address)
    signal picked(string address)

    objectName: "overviewTile"
    x: cell.x + offX
    y: cell.y + offY
    width: Math.max(8, Math.min(cell.width - offX, (windowData?.size[0] ?? 0) * deskScale))
    height: Math.max(8, Math.min(cell.height - offY, (windowData?.size[1] ?? 0) * deskScale))
    z: dragArea.drag.active ? 99999 : 1

    Item {
        id: body
        width: root.width
        height: root.height
        Drag.active: dragArea.drag.active
        Drag.hotSpot.x: width / 2
        Drag.hotSpot.y: height / 2

        ScreencopyView {
            anchors.fill: parent
            captureSource: GlobalStates.overviewOpen ? root.toplevel : null
            live: root.live
        }
        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.verysmall
            color: dragArea.pressed ? ColorUtils.transparentize(Appearance.colors.colLayer2Active, 0.5) : (root.hovered ? ColorUtils.transparentize(Appearance.colors.colLayer2Hover, 0.7) : ColorUtils.transparentize(Appearance.colors.colLayer2, 0.2))
            border.width: root.selected ? 3 : 1
            border.color: root.selected ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.m3colors.m3outline, 0.7)
        }
        AppIconPlate {
            anchors.centerIn: parent
            iconName: AppSearch.guessIcon(root.windowData?.class)
            label: root.windowData?.class ?? ""
            visible: Math.min(root.width, root.height) >= 40
            size: Math.min(96, Math.min(root.width, root.height) * 0.45)
        }
        Rectangle {
            visible: (root.hovered || root.selected || root.showTitle) && !dragArea.drag.active
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }
            height: titleText.implicitHeight + 8
            color: ColorUtils.transparentize(Appearance.m3colors.m3scrim, 0.35)
            StyledText {
                id: titleText
                anchors {
                    fill: parent
                    leftMargin: 8
                    rightMargin: 8
                }
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                text: root.windowData?.title || root.windowData?.class || ""
                color: "#ffffff"
            }
        }
    }

    MouseArea {
        id: dragArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        drag.target: body
        onPressed: mouse => {
            dragArea.drag.target = mouse.button === Qt.LeftButton ? body : null;
        }
        onReleased: {
            root.released(root.address);
            body.x = 0;
            body.y = 0;
        }
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton)
                Hyprland.dispatch(`hl.dsp.window.close({ window = "address:${root.address}" })`);
            else
                root.picked(root.address);
        }
    }
}

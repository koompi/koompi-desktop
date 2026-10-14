import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Loader {
    id: root
    // the colours of the surface it is drawn on: the bar's glass may be the other tone (BarScheme)
    readonly property BarScheme barScheme: root.QsWindow.window?.barScheme ?? ownBarScheme
    BarScheme {
        id: ownBarScheme
    }
    property bool vertical: false
    property color color: root.barScheme.subtext
    active: HyprlandXkb.layoutCodes.length > 1
    visible: active

    function abbreviateLayoutCode(fullCode) {
    return fullCode.split(':').map(layout => {
            const baseLayout = layout.split('-')[0];
            return baseLayout.slice(0, 4);
        }).join('\n');
    }

    sourceComponent: Item {
        implicitWidth: root.vertical ? null : layoutCodeText.implicitWidth
        implicitHeight: root.vertical ? layoutCodeText.implicitHeight : null

        StyledText {
            id: layoutCodeText
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            text: abbreviateLayoutCode(HyprlandXkb.currentLayoutCode)
            font.pixelSize: text.includes("\n") ? Appearance.font.pixelSize.smallie : Appearance.font.pixelSize.small
            color: root.color
            animateChange: true
        }

        // a click moves to the next layout, as Super+Space does
        MouseArea {
            id: layoutHover
            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", "next"])
        }
        PopupToolTip {
            extraVisibleCondition: layoutHover.containsMouse
            anchorEdges: (!Config.options.bar.bottom && !Config.options.bar.vertical) ? Edges.Bottom : Edges.Top
            text: HyprlandXkb.currentLayoutName + "\n" + Translation.tr("Click or Super+Space to switch")
        }
    }
}

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell

// The network glyph. A click opens the right panel with the network list dropped down.
MaterialSymbol {
    id: root
    objectName: "networkIndicator"

    text: Network.materialSymbol
    fill: Network.connected ? 1 : 0
    iconSize: Appearance.font.pixelSize.larger
    color: Appearance.colors.colOnLayer0

    MouseArea {
        id: networkHover
        anchors.fill: parent
        anchors.margins: -4 // a glyph is a small target
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: GlobalStates.toggleSidebarRightOn("wifi")
    }
    PopupToolTip {
        extraVisibleCondition: networkHover.containsMouse
        anchorEdges: (!Config.options.bar.bottom && !Config.options.bar.vertical) ? Edges.Bottom : Edges.Top
        text: (Network.networkName !== "" ? Network.networkName : Translation.tr("Not connected")) + "\n" + Translation.tr("Click to see networks")
    }
}

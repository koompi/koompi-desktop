import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell

// The network glyph. A click opens the right panel with the network list dropped down.
MaterialSymbol {
    id: root
    // the colours of the surface it is drawn on: the bar's glass may be the other tone (BarScheme)
    readonly property BarScheme barScheme: root.QsWindow.window?.barScheme ?? ownBarScheme
    BarScheme {
        id: ownBarScheme
    }
    objectName: "networkIndicator"

    text: Network.materialSymbol
    fill: Network.connected ? 1 : 0
    iconSize: Appearance.font.pixelSize.larger
    color: root.barScheme.fg

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

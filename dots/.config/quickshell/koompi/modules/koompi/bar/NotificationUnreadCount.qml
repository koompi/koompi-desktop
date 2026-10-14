import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Quickshell

// the dot on the clock while notifications wait; the count only if bar.indicators.notifications.showUnreadCount is on
Rectangle {
    id: root
    // the colours of the surface it is drawn on: the bar's glass may be the other tone (BarScheme)
    readonly property BarScheme barScheme: root.QsWindow.window?.barScheme ?? ownBarScheme
    BarScheme {
        id: ownBarScheme
    }
    objectName: "unreadDot"
    readonly property bool showUnreadCount: Config.options.bar.indicators.notifications.showUnreadCount
    color: root.barScheme.fg

    visible: !Notifications.silent && Notifications.unread > 0
    radius: Appearance.rounding.full
    implicitHeight: root.showUnreadCount ? Math.max(countText.implicitWidth, countText.implicitHeight) : 7
    implicitWidth: implicitHeight
    border.width: 1
    border.color: root.barScheme.worstCase

    StyledText {
        id: countText
        visible: root.showUnreadCount
        anchors.centerIn: parent
        font.pixelSize: Appearance.font.pixelSize.smallest
        color: root.barScheme.worstCase
        text: Notifications.unread
    }
}

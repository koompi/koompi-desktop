import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// the dot on the clock while notifications wait; the count only if bar.indicators.notifications.showUnreadCount is on
Rectangle {
    id: root
    objectName: "unreadDot"
    readonly property bool showUnreadCount: Config.options.bar.indicators.notifications.showUnreadCount
    color: Appearance.colors.colOnLayer0

    visible: !Notifications.silent && Notifications.unread > 0
    radius: Appearance.rounding.full
    implicitHeight: root.showUnreadCount ? Math.max(countText.implicitWidth, countText.implicitHeight) : 7
    implicitWidth: implicitHeight
    border.width: 1
    border.color: Appearance.colors.colBarWorstCase

    StyledText {
        id: countText
        visible: root.showUnreadCount
        anchors.centerIn: parent
        font.pixelSize: Appearance.font.pixelSize.smallest
        color: Appearance.colors.colBarWorstCase
        text: Notifications.unread
    }
}

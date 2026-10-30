import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// The bell: opens the right panel, where the notifications are, as the sliders glyph and the
// clock beside it do. The unread dot sits on its shoulder. Do Not Disturb has its own light
// among the mode indicators, so the bell does not change for it.
BarPanelButton {
    id: root
    objectName: "notificationButton"
    toggled: GlobalStates.sidebarRightOpen
    tooltip: Translation.tr("Notifications")
    onClicked: GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen

    contentItem: Item {
        implicitWidth: bell.implicitWidth
        implicitHeight: bell.implicitHeight

        MaterialSymbol {
            id: bell
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: "notifications"
            fill: GlobalStates.sidebarRightOpen ? 1 : 0
            iconSize: Appearance.font.pixelSize.larger
            color: root.colText
        }

        // over the bell's corner rather than beside it, so the bar does not shift when one arrives
        NotificationUnreadCount {
            anchors {
                right: bell.right
                top: bell.top
                rightMargin: -1
                topMargin: 1
            }
        }
    }
}

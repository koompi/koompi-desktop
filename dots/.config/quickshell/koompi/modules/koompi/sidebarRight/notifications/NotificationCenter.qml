import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// Notifications grouped by app, each group with its own clear, then Clear all, then the System group.
Item {
    id: root
    // NotificationGroup reads its swipe-to-dismiss state from the item two levels up
    property int dragIndex: -1
    property real dragDistance: 0
    function resetDrag() {
        dragIndex = -1;
        dragDistance = 0;
    }

    implicitHeight: column.implicitHeight

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Appearance.spacing.small

        StyledText {
            visible: Notifications.list.length === 0
            Layout.fillWidth: true
            Layout.topMargin: Appearance.spacing.normal
            Layout.bottomMargin: Appearance.spacing.normal
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            text: Translation.tr("No notifications")
        }

        Repeater {
            model: Notifications.panelAppNameList
            delegate: NotificationGroup {
                required property int index
                required property string modelData
                objectName: "nc-group-" + modelData
                Layout.fillWidth: true
                clearable: true
                notificationGroup: Notifications.panelGroupsByAppName[modelData]
            }
        }

        RippleButton {
            objectName: "nc-clear-all"
            visible: Notifications.list.length > 0
            Layout.alignment: Qt.AlignRight
            implicitHeight: 32
            horizontalPadding: Appearance.spacing.normal
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colLayer1
            buttonText: Translation.tr("Clear all")
            onClicked: Notifications.discardAllNotifications()
        }

        SystemGroup {}
    }
}

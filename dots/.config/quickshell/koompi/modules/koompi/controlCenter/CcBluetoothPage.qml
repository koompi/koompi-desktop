import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.koompi.sidebarRight.bluetoothDevices
import QtQuick
import QtQuick.Layouts
import Quickshell

ColumnLayout {
    id: root
    spacing: Appearance.spacing.small

    Component.onCompleted: BluetoothStatus.setDiscovering(BluetoothStatus.enabled)
    Component.onDestruction: BluetoothStatus.setDiscovering(false)

    StyledIndeterminateProgressBar {
        visible: BluetoothStatus.discovering
        Layout.fillWidth: true
    }

    StyledListView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: 0
        animateAppearance: false
        model: ScriptModel {
            values: BluetoothStatus.friendlyDeviceList
        }
        delegate: BluetoothDeviceItem {
            required property var modelData
            device: modelData
            anchors {
                left: parent?.left
                right: parent?.right
            }
        }
    }

    CcLinkRow {
        buttonText: Translation.tr("More Bluetooth settings")
        page: "bluetooth"
    }
}

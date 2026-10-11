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

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Appearance.spacing.normal
        Layout.rightMargin: Appearance.spacing.normal
        StyledText {
            Layout.fillWidth: true
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.DemiBold
            color: Appearance.colors.colSubtext
            text: BluetoothStatus.enabled ? Translation.tr("Devices") : Translation.tr("Bluetooth is off")
        }
        CcSwitch {
            objectName: "cc-bluetooth-list-switch"
            checked: BluetoothStatus.enabled
            label: Translation.tr("Bluetooth")
            onFlipped: BluetoothStatus.setEnabled(!BluetoothStatus.enabled)
        }
    }

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
        buttonText: Translation.tr("More settings…")
        page: "bluetooth"
    }
}

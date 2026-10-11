import qs
import qs.services
import qs.services.network
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.koompi.sidebarRight.wifiNetworks
import QtQuick
import QtQuick.Layouts
import Quickshell

ColumnLayout {
    id: root
    spacing: Appearance.spacing.small

    Component.onCompleted: Network.rescanWifi()

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Appearance.spacing.normal
        Layout.rightMargin: Appearance.spacing.normal
        StyledText {
            Layout.fillWidth: true
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.DemiBold
            color: Appearance.colors.colSubtext
            text: Network.wifiEnabled ? Translation.tr("Available networks") : Translation.tr("Wi-Fi is off")
        }
        CcSwitch {
            objectName: "cc-wifi-list-switch"
            checked: Network.wifiEnabled
            label: Translation.tr("Wi-Fi")
            onFlipped: Network.toggleWifi()
        }
    }

    StyledIndeterminateProgressBar {
        visible: Network.wifiScanning
        Layout.fillWidth: true
    }

    ListView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: 0
        model: ScriptModel {
            values: Network.friendlyWifiNetworks
        }
        delegate: WifiNetworkItem {
            required property WifiAccessPoint modelData
            wifiNetwork: modelData
            width: ListView.view.width
        }
    }

    CcLinkRow {
        buttonText: Translation.tr("More settings…")
        page: "network"
    }
}

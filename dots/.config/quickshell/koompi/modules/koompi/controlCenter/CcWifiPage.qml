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
        buttonText: Translation.tr("More Wi-Fi settings")
        page: "network"
    }
}

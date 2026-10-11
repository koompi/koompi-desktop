import qs
import qs.modules.common
import qs.modules.settings
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    readonly property bool built: surface.item !== null
    readonly property bool shown: surface.item?.visible ?? false
    readonly property int pageShown: surface.item?.contentItem.currentPage ?? -1
    property string requestedPage: ""

    function open(page: string): void {
        root.requestedPage = page;
        GlobalStates.settingsOpen = true;
        if (page.length > 0)
            surface.item?.contentItem.showPage(page);
    }

    function close(): void {
        GlobalStates.settingsOpen = false;
    }

    function toggle(): void {
        if (GlobalStates.settingsOpen)
            root.close();
        else
            root.open("");
    }

    LazySurface {
        id: surface
        open: GlobalStates.settingsOpen

        component: FloatingWindow {
            id: window
            // the window rules in hypr/hyprland/rules.lua match this title
            title: "KOOMPI Settings"
            visible: GlobalStates.settingsOpen
            implicitWidth: 1100
            implicitHeight: 750
            minimumSize: Qt.size(750, 500)
            color: Appearance.m3colors.m3background
            property alias contentItem: content

            onVisibleChanged: {
                if (!visible)
                    GlobalStates.settingsOpen = false;
            }

            SettingsContent {
                id: content
                anchors.fill: parent
                initialPage: root.requestedPage
                onCloseRequested: GlobalStates.settingsOpen = false
            }
        }
    }

    IpcHandler {
        target: "settings"

        function open(): void {
            root.open("");
        }

        function close(): void {
            root.close();
        }

        function toggle(): void {
            root.toggle();
        }

        function page(name: string): void {
            root.open(name);
        }
    }
}

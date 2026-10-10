import qs
import qs.services
import qs.modules.common
import Quickshell.Io
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// The workspace grid. It owns GlobalStates.overviewOpen and reads no other
// panel's flag, so search opening or closing never moves this window.
Scope {
    id: root
    readonly property bool built: surface.item !== null

    // Shares the search surface's layer namespace; see SearchPanel.qml.
    readonly property string layerNamespace: "quickshell:overview"

    function close() {
        GlobalStates.overviewOpen = false;
    }

    function toggle() {
        GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
    }

    LazySurface {
        id: surface
        open: GlobalStates.overviewOpen

        component: PanelWindow {
            id: overviewWindow
            visible: GlobalStates.overviewOpen

            WlrLayershell.namespace: root.layerNamespace
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: GlobalStates.overviewOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            color: "transparent"

            property alias widget: overviewLoader.item

            mask: Region {
                item: GlobalStates.overviewOpen ? overviewLayout : null
            }

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            onVisibleChanged: {
                if (overviewWindow.visible) {
                    GlobalFocusGrab.addDismissable(overviewWindow);
                } else {
                    GlobalFocusGrab.removeDismissable(overviewWindow);
                }
            }

            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    root.close();
                }
            }

            Item {
                id: overviewLayout
                anchors.fill: parent
                visible: GlobalStates.overviewOpen

                Rectangle {
                    anchors.fill: parent
                    color: Appearance.colors.colScrim
                }

                Loader {
                    id: overviewLoader
                    anchors.fill: parent
                    active: GlobalStates.overviewOpen && (Config?.options.overview.enable ?? true)
                    sourceComponent: OverviewWidget {
                        screen: overviewWindow.screen
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "overview"

        function state(): string {
            return JSON.stringify(surface.item?.widget?.snapshot() ?? {});
        }
    }

    GlobalShortcut {
        name: "overviewWorkspacesClose"
        description: "Closes overview on press"

        onPressed: {
            root.close();
        }
    }

    GlobalShortcut {
        name: "overviewWorkspacesToggle"
        description: "Toggles overview on press"

        onPressed: {
            root.toggle();
        }
    }
}

import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: launchpadScope
    readonly property bool built: surface.item !== null

    LazySurface {
        id: surface
        open: GlobalStates.launchpadOpen

        component: PanelWindow {
            id: panelWindow
            visible: GlobalStates.launchpadOpen

            // one-shot: arrive() replaces this binding, so the surface never migrates mid-session
            property var targetScreen: panelWindow.focusedScreen()
            screen: targetScreen
            // lets the content fade in on a cold open too
            property bool shown: false

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:launchpad"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: GlobalStates.launchpadOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            function focusedScreen() {
                return Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null;
            }

            function arrive() {
                panelWindow.targetScreen = panelWindow.focusedScreen();
                content.reset();
            }

            Component.onCompleted: {
                panelWindow.arrive();
                panelWindow.shown = true;
            }

            Connections {
                target: GlobalStates
                function onLaunchpadOpenChanged() {
                    if (GlobalStates.launchpadOpen)
                        panelWindow.arrive();
                }
            }

            LaunchpadContent {
                id: content
                anchors.fill: parent
                active: panelWindow.shown && GlobalStates.launchpadOpen
            }
        }
    }

    IpcHandler {
        target: "launchpad"

        function toggle() {
            GlobalStates.launchpadOpen = !GlobalStates.launchpadOpen;
        }
        function open() {
            GlobalStates.launchpadOpen = true;
        }
        function close() {
            GlobalStates.launchpadOpen = false;
        }
    }

    GlobalShortcut {
        name: "launchpadToggle"
        description: "Toggles the Launchpad app grid"

        onPressed: {
            GlobalStates.launchpadOpen = !GlobalStates.launchpadOpen;
        }
    }

    // Open and close are separate so the pinch-in / pinch-out pair is not a
    // toggle: pinching in twice should leave it open, not flap it shut.
    GlobalShortcut {
        name: "launchpadOpen"
        description: "Opens the Launchpad app grid"

        onPressed: {
            GlobalStates.launchpadOpen = true;
        }
    }

    GlobalShortcut {
        name: "launchpadClose"
        description: "Closes the Launchpad app grid"

        onPressed: {
            GlobalStates.launchpadOpen = false;
        }
    }
}

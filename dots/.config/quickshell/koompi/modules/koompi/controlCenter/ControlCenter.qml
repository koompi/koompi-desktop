import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    readonly property bool built: surface.item !== null
    readonly property var content: surface.item?.content ?? null
    readonly property var pages: ["wifi", "bluetooth", "display", "sound", "nowPlaying", "battery", "edit"]

    // the focused monitor as it was before the panel opened, so the window is built there and stays put
    property var targetScreen: null
    property string requestedPage: ""

    function focusedScreen() {
        const name = Hyprland.focusedMonitor?.name;
        return Quickshell.screens.find(screen => screen.name === name) ?? null;
    }

    function takeRequestedPage(): string {
        const page = root.requestedPage;
        root.requestedPage = "";
        return page;
    }

    function showModule(name: string): void {
        if (root.pages.indexOf(name) < 0)
            return;
        if (root.content)
            root.content.showPage(name);
        else
            root.requestedPage = name;
        GlobalStates.controlCenterOpen = true;
    }

    Binding {
        target: root
        property: "targetScreen"
        value: root.focusedScreen()
        when: !GlobalStates.controlCenterOpen
    }

    LazySurface {
        id: surface
        open: GlobalStates.controlCenterOpen

        component: PanelWindow {
            id: panelWindow
            property alias content: content
            readonly property real cardMargin: Appearance.sizes.elevationMargin
            // 0 tucked under the bar, 1 fully down. The window starts at the bar's lower edge and
            // clips, so the card slides out from beneath the bar instead of across it.
            property real reveal: 0

            visible: GlobalStates.controlCenterOpen || reveal > 0
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            implicitWidth: content.implicitWidth + cardMargin * 2
            implicitHeight: content.implicitHeight + cardMargin * 2
            color: "transparent"
            WlrLayershell.namespace: "quickshell:controlCenter"
            WlrLayershell.keyboardFocus: GlobalStates.controlCenterOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

            anchors {
                top: true
                right: true
            }
            margins {
                top: Appearance.sizes.barHeight
                right: Appearance.sizes.hyprlandGapsOut
            }

            mask: Region {
                item: content
            }

            function updateDismissable() {
                if (panelWindow.visible)
                    GlobalFocusGrab.addDismissable(panelWindow);
                else
                    GlobalFocusGrab.removeDismissable(panelWindow);
            }

            onVisibleChanged: updateDismissable()
            Behavior on reveal {
                NumberAnimation {
                    duration: GlobalStates.controlCenterOpen ? Appearance.animation.elementMoveEnter.duration : Appearance.animation.elementMoveExit.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: GlobalStates.controlCenterOpen ? Appearance.animationCurves.emphasizedDecel : Appearance.animationCurves.emphasizedAccel
                }
            }
            Connections {
                target: GlobalStates
                function onControlCenterOpenChanged() {
                    panelWindow.reveal = GlobalStates.controlCenterOpen ? 1 : 0;
                }
            }

            Component.onCompleted: {
                Qt.callLater(() => panelWindow.reveal = GlobalStates.controlCenterOpen ? 1 : 0);
                if (root.targetScreen)
                    panelWindow.screen = root.targetScreen;
                updateDismissable();
                const page = root.takeRequestedPage();
                if (page.length > 0)
                    content.showPage(page);
            }
            Component.onDestruction: GlobalFocusGrab.removeDismissable(panelWindow)

            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    GlobalStates.controlCenterOpen = false;
                }
            }

            Item {
                id: drawer
                anchors.fill: parent
                clip: true

                StyledRectangularShadow {
                    target: content
                }

                ControlCenterContent {
                    id: content
                    x: panelWindow.cardMargin
                    y: panelWindow.cardMargin - (1 - panelWindow.reveal) * (height + panelWindow.cardMargin * 2)
                    focus: GlobalStates.controlCenterOpen
                    maxHeight: (panelWindow.screen?.height ?? 900) - Appearance.sizes.barHeight - Appearance.sizes.hyprlandGapsOut * 2 - panelWindow.cardMargin * 2
                    onCloseRequested: GlobalStates.controlCenterOpen = false
                }
            }
        }
    }

    IpcHandler {
        target: "controlCenter"

        function toggle(): void {
            GlobalStates.controlCenterOpen = !GlobalStates.controlCenterOpen;
        }

        function open(): void {
            GlobalStates.controlCenterOpen = true;
        }

        function close(): void {
            GlobalStates.controlCenterOpen = false;
        }

        function module(name: string): void {
            root.showModule(name);
        }
    }

    GlobalShortcut {
        name: "controlCenterToggle"
        description: "Toggles the Control Center on press"

        onPressed: GlobalStates.controlCenterOpen = !GlobalStates.controlCenterOpen
    }
}

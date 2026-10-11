import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    readonly property bool built: surface.item !== null
    property int sidebarWidth: Appearance.sizes.sidebarWidthRight

    readonly property bool pinned: Persistent.states.sidebar.pinned

    // a drawer asked for before the content exists; the content takes it as it is built
    property string pendingDrawer: ""
    property string pendingModule: ""
    readonly property var content: surface.item?.content ?? null

    function takePendingDrawer(): string {
        const page = root.pendingDrawer;
        root.pendingDrawer = "";
        return page;
    }

    function hide(): void {
        if (root.pinned)
            return;
        GlobalStates.sidebarRightOpen = false;
    }

    function showModule(name: string): void {
        if (["wifi", "bluetooth", "sound", "power", "display", "nowPlaying", "battery", "edit"].indexOf(name) < 0)
            return;
        if (root.content)
            root.content.showModule(name);
        else
            root.pendingModule = name;
        GlobalStates.sidebarRightOpen = true;
    }

    function showDrawer(page: string): void {
        const content = root.content;
        if (content && content.drawer === page) {
            content.drawer = "";
            root.hide();
            return;
        }
        if (content)
            content.drawer = page;
        else
            root.pendingDrawer = page;
        GlobalStates.sidebarRightOpen = true;
    }

    onPinnedChanged: {
        if (root.pinned)
            GlobalStates.sidebarRightOpen = true;
    }

    LazySurface {
        id: surface
        open: GlobalStates.sidebarRightOpen || root.pinned || Config?.options.sidebar.keepRightSidebarLoaded

        component: PanelWindow {
            id: panelWindow
            // 0 tucked under the bar, 1 fully down: the window starts at the bar's lower edge and clips,
            // so the card comes out from beneath the bar instead of across it
            property real reveal: 0
            readonly property bool wanted: GlobalStates.sidebarRightOpen || root.pinned
            visible: wanted || reveal > 0
            property alias content: sidebarContentLoader.item

            // Reserve up to the panel's visible edge, not the whole window: the left
            // elevationMargin is shadow room, and reserving it too doubles the gap.
            exclusiveZone: root.pinned ? root.sidebarWidth - Appearance.sizes.elevationMargin : 0
            implicitWidth: root.sidebarWidth
            WlrLayershell.namespace: "quickshell:sidebarRight"
            WlrLayershell.keyboardFocus: GlobalStates.sidebarRightOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            color: "transparent"

            anchors {
                top: true
                right: true
                bottom: true
            }
            // No top margin: the window respects the bar's exclusive zone, so the compositor already
            // starts it at the bar's lower edge. A barHeight margin on top of that doubled the top gap.

            onWantedChanged: reveal = wanted ? 1 : 0
            Component.onCompleted: Qt.callLater(() => panelWindow.reveal = panelWindow.wanted ? 1 : 0)
            Behavior on reveal {
                NumberAnimation {
                    duration: panelWindow.wanted ? Appearance.animation.elementMoveEnter.duration : Appearance.animation.elementMoveExit.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: panelWindow.wanted ? Appearance.animationCurves.emphasizedDecel : Appearance.animationCurves.emphasizedAccel
                }
            }

            // A pinned panel is not dismissable, so clicking away leaves it alone.
            function updateDismissable() {
                if (panelWindow.visible && !root.pinned) {
                    GlobalFocusGrab.addDismissable(panelWindow);
                } else {
                    GlobalFocusGrab.removeDismissable(panelWindow);
                }
            }
            onVisibleChanged: updateDismissable()
            Connections {
                target: root
                function onPinnedChanged() {
                    panelWindow.updateDismissable();
                }
            }
            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    root.hide();
                }
            }

            Item {
                anchors.fill: parent
                clip: true

                // a Loader sizes the content before its bindings run; bare anchors log a binding loop on implicitHeight
                Loader {
                    id: sidebarContentLoader
                    anchors {
                        fill: parent
                        margins: Appearance.sizes.hyprlandGapsOut
                        leftMargin: Appearance.sizes.elevationMargin
                    }

                    focus: GlobalStates.sidebarRightOpen
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            if (sidebarContentLoader.item?.back())
                                return;
                            root.hide();
                        }
                    }

                    sourceComponent: SidebarRightContent {}

                    onLoaded: {
                        item.drawer = root.takePendingDrawer();
                        const module = root.pendingModule;
                        root.pendingModule = "";
                        if (module.length > 0)
                            item.showModule(module);
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "sidebarRight"

        function toggle(): void {
            GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
        }

        function close(): void {
            GlobalStates.sidebarRightOpen = false;
        }

        function open(): void {
            GlobalStates.sidebarRightOpen = true;
        }

        function drawer(page: string): void {
            root.showDrawer(page);
        }
    }

    IpcHandler {
        target: "controlCenter"

        function toggle(): void {
            GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
        }

        function open(): void {
            GlobalStates.sidebarRightOpen = true;
        }

        function close(): void {
            GlobalStates.sidebarRightOpen = false;
        }

        function module(name: string): void {
            root.showModule(name);
        }
    }

    GlobalShortcut {
        name: "controlCenterToggle"
        description: "Toggles the right panel on press (the old Control Center name)"

        onPressed: GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen
    }

    GlobalShortcut {
        name: "sidebarRightToggle"
        description: "Toggles right sidebar on press"

        onPressed: {
            GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
        }
    }
    GlobalShortcut {
        name: "sidebarRightOpen"
        description: "Opens right sidebar on press"

        onPressed: {
            GlobalStates.sidebarRightOpen = true;
        }
    }
    GlobalShortcut {
        name: "sidebarRightClose"
        description: "Closes right sidebar on press"

        onPressed: {
            GlobalStates.sidebarRightOpen = false;
        }
    }

    GlobalShortcut {
        name: "sidebarRightCalendar"
        description: "Opens the right sidebar on the calendar"

        onPressed: root.showDrawer("calendar")
    }
    GlobalShortcut {
        name: "sidebarRightTodo"
        description: "Opens the right sidebar on the to-do list"

        onPressed: root.showDrawer("todo")
    }
    GlobalShortcut {
        name: "sidebarRightTimer"
        description: "Opens the right sidebar on the timer"

        onPressed: root.showDrawer("timer")
    }
}

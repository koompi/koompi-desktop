import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope { // Scope
    id: root
    readonly property bool built: surface.item !== null
    property bool detach: false
    property bool pin: false
    property bool extend: false
    property Component contentComponent: SidebarLeftContent {}

    function toggleDetach() {
        root.detach = !root.detach;
    }

    // the memory daemon loads an embedding model, so it starts with the first open and not at login
    Connections {
        target: GlobalStates
        function onSidebarLeftOpenChanged() {
            if (!GlobalStates.sidebarLeftOpen) return;
            MemoryService.load();
            // Every open, not once: litert-lm.socket unloads the engine after
            // 5min idle, so the list and the warm both have to be re-done.
            Ai.refreshLitertLmModels();
        }
    }

    Process { // Dodge cursor away, pin, move cursor back
        id: pinWithFunnyHyprlandWorkaroundProc
        property var hook: null
        property int cursorX;
        property int cursorY;
        function doIt() {
            command = ["hyprctl", "cursorpos"]
            hook = (output) => {
                cursorX = parseInt(output.split(",")[0]);
                cursorY = parseInt(output.split(",")[1]);
                doIt2();
            }
            running = true;
        }
        function doIt2(output) {
            command = ["bash", "-c", "hyprctl dispatch 'hl.dsp.cursor.move({x=9999,y=9999})'"];
            hook = () => {
                doIt3();
            }
            running = true;
        }
        function doIt3(output) {
            root.pin = !root.pin;
            command = ["bash", "-c", `sleep 0.01; hyprctl dispatch 'hl.dsp.cursor.move({x=${cursorX},y=${cursorY}})'`];
            hook = null
            running = true;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                pinWithFunnyHyprlandWorkaroundProc.hook(text);
            }
        }
    }

    function togglePin() {
        if (!root.pin) pinWithFunnyHyprlandWorkaroundProc.doIt()
        else root.pin = !root.pin;
    }

    LazySurface {
        id: surface
        open: GlobalStates.sidebarLeftOpen

        component: Scope {
            id: windows
            property Item sidebarContent

            // one content moves between the docked and the detached window, so a detach keeps what was typed
            function place() {
                const loader = root.detach ? detachedSidebarLoader : sidebarLoader;
                loader.active = true;
                loader.item.contentParent.children = [windows.sidebarContent];
            }

            Component.onCompleted: {
                windows.sidebarContent = root.contentComponent.createObject(null, {
                    "scopeRoot": root,
                });
                windows.place();
            }
            Component.onDestruction: windows.sidebarContent?.destroy()

            Connections {
                target: root
                function onDetachChanged() {
                    if (root.detach)
                        GlobalFocusGrab.removeDismissable(sidebarLoader.item);
                    windows.sidebarContent.parent = null;
                    if (root.detach)
                        sidebarLoader.active = false;
                    else
                        detachedSidebarLoader.active = false;
                    windows.place();
                }
            }

            Loader {
                id: sidebarLoader
                active: false

                sourceComponent: PanelWindow { // Window
                    id: panelWindow
                    visible: GlobalStates.sidebarLeftOpen

                    readonly property real screenWidth: panelWindow.screen?.width ?? 0
                    readonly property real widthNormal: screenWidth > 0
                        ? Math.round(screenWidth * Appearance.sizes.sidebarWidthFraction)
                        : Appearance.sizes.sidebarWidth
                    readonly property real widthExtended: screenWidth > 0
                        ? Math.round(screenWidth * Appearance.sizes.sidebarWidthExtendedFraction)
                        : Appearance.sizes.sidebarWidthExtended
                    property real sidebarWidth: root.extend ? widthExtended : widthNormal
                    property var contentParent: sidebarLeftBackground

                    function hide() {
                        GlobalStates.sidebarLeftOpen = false
                    }

                    exclusionMode: ExclusionMode.Normal
                    exclusiveZone: root.pin ? sidebarWidth : 0
                    implicitWidth: panelWindow.widthExtended + Appearance.sizes.elevationMargin
                    WlrLayershell.namespace: "quickshell:sidebarLeft"
                    // Hyprland 0.49: OnDemand is Exclusive, Exclusive just breaks click-outside-to-close
                    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
                    color: "transparent"

                    anchors {
                        top: true
                        left: true
                        bottom: true
                    }

                    mask: Region {
                        item: sidebarLeftBackground
                    }

                    onVisibleChanged: {
                        if (visible) {
                            GlobalFocusGrab.addDismissable(panelWindow);
                        } else {
                            GlobalFocusGrab.removeDismissable(panelWindow);
                        }
                    }
                    Connections {
                        target: GlobalFocusGrab
                        function onDismissed() {
                            panelWindow.hide();
                        }
                    }

                    // Content
                    StyledRectangularShadow {
                        target: sidebarLeftBackground
                        radius: sidebarLeftBackground.radius
                    }
                    Rectangle {
                        id: sidebarLeftBackground
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.topMargin: Appearance.sizes.hyprlandGapsOut
                        anchors.leftMargin: Appearance.sizes.hyprlandGapsOut
                        width: panelWindow.sidebarWidth - Appearance.sizes.hyprlandGapsOut - Appearance.sizes.elevationMargin
                        height: parent.height - Appearance.sizes.hyprlandGapsOut * 2
                        color: Appearance.colors.colLayer0
                        border.width: 1
                        border.color: Appearance.colors.colLayer0Border
                        radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

                        Behavior on width {
                            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                        }

                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_Escape) {
                                panelWindow.hide();
                            }
                            if (event.modifiers === Qt.ControlModifier) {
                                if (event.key === Qt.Key_O) {
                                    root.extend = !root.extend;
                                } else if (event.key === Qt.Key_D) {
                                    root.toggleDetach();
                                } else if (event.key === Qt.Key_P) {
                                    root.togglePin();
                                }
                                event.accepted = true;
                            }
                        }
                    }
                }
            }

            Loader {
                id: detachedSidebarLoader
                active: false

                sourceComponent: FloatingWindow {
                    id: detachedSidebarRoot
                    property var contentParent: detachedSidebarBackground
                    color: "transparent"

                    visible: GlobalStates.sidebarLeftOpen
                    onVisibleChanged: {
                        if (!visible) GlobalStates.sidebarLeftOpen = false;
                    }
            
                    Rectangle {
                        id: detachedSidebarBackground
                        anchors.fill: parent
                        color: Appearance.colors.colLayer0

                        Keys.onPressed: (event) => {
                            if (event.modifiers === Qt.ControlModifier) {
                                if (event.key === Qt.Key_D) {
                                    root.toggleDetach();
                                }
                                event.accepted = true;
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "sidebarLeft"

        function toggle(): void {
            GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen
        }

        function close(): void {
            GlobalStates.sidebarLeftOpen = false
        }

        function open(): void {
            GlobalStates.sidebarLeftOpen = true
        }
    }

    GlobalShortcut {
        name: "sidebarLeftToggle"
        description: "Toggles left sidebar on press"

        onPressed: {
            GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;
        }
    }

    GlobalShortcut {
        name: "sidebarLeftOpen"
        description: "Opens left sidebar on press"

        onPressed: {
            GlobalStates.sidebarLeftOpen = true;
        }
    }

    GlobalShortcut {
        name: "sidebarLeftClose"
        description: "Closes left sidebar on press"

        onPressed: {
            GlobalStates.sidebarLeftOpen = false;
        }
    }

    GlobalShortcut {
        name: "sidebarLeftToggleDetach"
        description: "Detach left sidebar into a window/Attach it back"

        onPressed: {
            root.detach = !root.detach;
        }
    }

}

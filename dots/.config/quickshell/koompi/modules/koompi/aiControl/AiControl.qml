pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * The Control session's safety shell on screen: while the assistant has its own
 * browser open, or is working in the user's apps (desktop control), a pill under the
 * bar on the focused monitor says so and carries Pause and Stop. Super+Shift+Escape
 * stops from anywhere (D9; Super+Escape is Kiri's).
 *
 * Take-over: other than the focus the agent's own steps cause (a step in flight, or one
 * that just answered), the user focusing the agent's browser window pauses the session,
 * and so does switching to any window while desktop control is on; the next step asks
 * before it runs. Typing into a window that already has focus is not visible to the
 * shell, so the Pause button is the dependable way to take over.
 */
Scope {
    id: root

    // a step that just answered may have opened or raised the window itself
    readonly property int selfFocusGraceMs: 1500
    readonly property var focusedScreen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null
    readonly property bool active: Ai.browserActive || Ai.desktopActive
    readonly property bool paused: (Ai.browserActive && Ai.browserPaused) || (Ai.desktopActive && Ai.desktopPaused)

    Connections {
        target: Hyprland
        enabled: (Ai.browserActive && !Ai.browserPaused) || (Ai.desktopActive && !Ai.desktopPaused)
        function onRawEvent(event) {
            if (event.name !== "activewindowv2") return;
            const now = Date.now();
            if (Ai.browserBusy || now - Ai.browserLastReplyAt < root.selfFocusGraceMs) return;
            if (Ai.desktopBusy || now - Ai.desktopLastReplyAt < root.selfFocusGraceMs) return;
            // a window, not focus leaving for a layer (the chat) or for nothing
            if (Ai.desktopActive && /^(0x)?[0-9a-f]+$/i.test(`${event.data}`.trim())) {
                Ai.pauseControl();
                return;
            }
            focusedPid.running = false;
            focusedPid.running = true;
        }
    }

    Process {
        id: focusedPid
        command: ["hyprctl", "-j", "activewindow"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    if (Ai.browserPid > 0 && JSON.parse(text).pid === Ai.browserPid) Ai.pauseControl();
                } catch (e) {}
            }
        }
    }

    // the pill window while it exists, null when released (tests/test_ai_control.sh reads it)
    readonly property var window: surface.item

    LazySurface {
        id: surface
        open: root.active
        keepWarm: 0
        component: PanelWindow {
            id: pill
            objectName: "aiControlPill"
            screen: root.focusedScreen
            visible: root.active
            color: "transparent"
            WlrLayershell.namespace: "quickshell:aiControl"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            anchors {
                top: !Config.options.bar.bottom
                bottom: Config.options.bar.bottom
            }
            margins {
                top: Appearance.sizes.barHeight + Appearance.spacing.normal
                bottom: Appearance.sizes.barHeight + Appearance.spacing.normal
            }
            // room around the pill for its shadow
            implicitWidth: body.implicitWidth + Appearance.spacing.large * 2 + Appearance.sizes.elevationMargin * 2
            implicitHeight: body.implicitHeight + Appearance.spacing.normal * 2 + Appearance.sizes.elevationMargin * 2
            mask: Region { item: background }

            StyledRectangularShadow { target: background }
            Rectangle {
                id: background
                anchors.fill: parent
                anchors.margins: Appearance.sizes.elevationMargin
                radius: Appearance.rounding.full
                color: root.paused ? Appearance.colors.colLayer2 : Appearance.colors.colErrorContainer

                RowLayout {
                    id: body
                    anchors.centerIn: parent
                    spacing: Appearance.spacing.normal

                    MaterialSymbol {
                        text: root.paused ? "pause_circle" : Ai.desktopActive ? "touch_app" : "travel_explore"
                        iconSize: Appearance.font.pixelSize.hugeass
                        color: root.paused ? Appearance.colors.colOnLayer2 : Appearance.colors.colOnErrorContainer
                    }

                    ColumnLayout {
                        spacing: 0
                        StyledText {
                            objectName: "aiControlState"
                            text: root.paused ? Translation.tr("Paused")
                                : Ai.desktopActive ? Translation.tr("The assistant is using your apps")
                                : Translation.tr("The assistant is using its browser")
                            font.weight: Font.DemiBold
                            color: root.paused ? Appearance.colors.colOnLayer2 : Appearance.colors.colOnErrorContainer
                        }
                        StyledText { // the window it works in, or the page it is on, as they title themselves
                            Layout.maximumWidth: 320
                            visible: text.length > 0
                            text: Ai.desktopActive ? Ai.desktopWindow : Ai.browserTitle
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: root.paused ? Appearance.colors.colSubtext : Appearance.colors.colOnErrorContainer
                        }
                    }

                    DialogButton {
                        objectName: "aiControlPause"
                        buttonText: root.paused ? Translation.tr("Resume") : Translation.tr("Pause")
                        colEnabled: root.paused ? Appearance.colors.colPrimary : Appearance.colors.colOnErrorContainer
                        onClicked: root.paused ? Ai.resumeControl() : Ai.pauseControl()
                        StyledToolTip {
                            text: Ai.desktopActive ? Translation.tr("Take over yourself; the assistant asks before its next step")
                                : Translation.tr("Take the browser yourself; the assistant asks before its next step")
                        }
                    }

                    DialogButton {
                        objectName: "aiControlStop"
                        buttonText: Translation.tr("Stop")
                        colBackground: Appearance.colors.colError
                        colBackgroundHover: Appearance.colors.colErrorHover
                        colEnabled: Appearance.colors.colOnError
                        onClicked: Ai.stopControl()
                        StyledToolTip {
                            text: Ai.desktopActive ? Translation.tr("Stop the assistant and end its control of your apps (Super+Shift+Escape)")
                                : Translation.tr("Stop the assistant and close its browser (Super+Shift+Escape)")
                        }
                    }
                }
            }
        }
    }

    GlobalShortcut {
        name: "aiControlStop"
        description: "Stops the assistant's turn, closes its browser and ends its control of your apps"
        onPressed: Ai.stopControl()
    }

    IpcHandler {
        target: "aiControl"

        function stop(): void {
            Ai.stopControl();
        }
        function pause(): void {
            Ai.pauseControl();
        }
        function resume(): void {
            Ai.resumeControl();
        }
    }
}

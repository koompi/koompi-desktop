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
 * browser open, a pill under the bar on the focused monitor says so and carries
 * Pause and Stop. Super+Shift+Escape stops from anywhere (D9; Super+Escape is Kiri's).
 *
 * Take-over: the user focusing the agent's browser window, other than the focus its
 * own steps cause (a step in flight, or one that just answered), pauses the session,
 * and the next step asks before it runs. Typing into a window that already has focus
 * is not visible to the shell, so the Pause button is the dependable way to take over.
 */
Scope {
    id: root

    // a step that just answered may have opened or raised the window itself
    readonly property int selfFocusGraceMs: 1500
    readonly property var focusedScreen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null

    Connections {
        target: Hyprland
        enabled: Ai.browserActive && !Ai.browserPaused
        function onRawEvent(event) {
            if (event.name !== "activewindowv2") return;
            if (Ai.browserBusy || Date.now() - Ai.browserLastReplyAt < root.selfFocusGraceMs) return;
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
        open: Ai.browserActive
        keepWarm: 0
        component: PanelWindow {
            id: pill
            objectName: "aiControlPill"
            screen: root.focusedScreen
            visible: Ai.browserActive
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
                color: Ai.browserPaused ? Appearance.colors.colLayer2 : Appearance.colors.colErrorContainer

                RowLayout {
                    id: body
                    anchors.centerIn: parent
                    spacing: Appearance.spacing.normal

                    MaterialSymbol {
                        text: Ai.browserPaused ? "pause_circle" : "travel_explore"
                        iconSize: Appearance.font.pixelSize.hugeass
                        color: Ai.browserPaused ? Appearance.colors.colOnLayer2 : Appearance.colors.colOnErrorContainer
                    }

                    ColumnLayout {
                        spacing: 0
                        StyledText {
                            objectName: "aiControlState"
                            text: Ai.browserPaused ? Translation.tr("Paused") : Translation.tr("The assistant is using its browser")
                            font.weight: Font.DemiBold
                            color: Ai.browserPaused ? Appearance.colors.colOnLayer2 : Appearance.colors.colOnErrorContainer
                        }
                        StyledText { // the page it is on, as the page titles itself
                            Layout.maximumWidth: 320
                            visible: Ai.browserTitle.length > 0
                            text: Ai.browserTitle
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Ai.browserPaused ? Appearance.colors.colSubtext : Appearance.colors.colOnErrorContainer
                        }
                    }

                    DialogButton {
                        objectName: "aiControlPause"
                        buttonText: Ai.browserPaused ? Translation.tr("Resume") : Translation.tr("Pause")
                        colEnabled: Ai.browserPaused ? Appearance.colors.colPrimary : Appearance.colors.colOnErrorContainer
                        onClicked: Ai.browserPaused ? Ai.resumeControl() : Ai.pauseControl()
                        StyledToolTip {
                            text: Translation.tr("Take the browser yourself; the assistant asks before its next step")
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
                            text: Translation.tr("Stop the assistant and close its browser (Super+Shift+Escape)")
                        }
                    }
                }
            }
        }
    }

    GlobalShortcut {
        name: "aiControlStop"
        description: "Stops the assistant's turn and closes its browser"
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

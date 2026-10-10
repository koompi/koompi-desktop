import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    readonly property bool built: surface.item !== null
    property var focusedScreen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name)

    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked) {
                GlobalStates.sessionOpen = false;
            }
        }
    }

    LazySurface {
        id: surface
        open: GlobalStates.sessionOpen
        keepWarm: 0

        component: PanelWindow { // Session menu
            id: sessionRoot
            visible: GlobalStates.sessionOpen
            property string pending: ""
            property var origin: null
            readonly property var tiles: [sessionLock, sessionSleep, sessionHibernate, sessionLogout, sessionReboot, sessionShutdown, sessionTaskManager, sessionFirmwareReboot]
            readonly property var texts: ({
                    "poweroff": {
                        "many": Translation.tr("Shutting down in %1 seconds"),
                        "one": Translation.tr("Shutting down in %1 second"),
                        "now": Translation.tr("Shut down now")
                    },
                    "reboot": {
                        "many": Translation.tr("Restarting in %1 seconds"),
                        "one": Translation.tr("Restarting in %1 second"),
                        "now": Translation.tr("Restart now")
                    },
                    "firmware": {
                        "many": Translation.tr("Restarting to firmware setup in %1 seconds"),
                        "one": Translation.tr("Restarting to firmware setup in %1 second"),
                        "now": Translation.tr("Restart now")
                    }
                })

            Component.onCompleted: {
                SessionWarnings.refresh();
                sessionLock.forceActiveFocus();
            }

            function hide() {
                pending = "";
                GlobalStates.sessionOpen = false;
            }

            function begin(kind, tile) {
                origin = tile;
                pending = kind;
            }

            function cancel() {
                pending = "";
                (origin ?? sessionLock).forceActiveFocus();
            }

            function back() {
                if (pending !== "")
                    cancel();
                else
                    hide();
            }

            function commit() {
                const kind = pending;
                hide();
                if (kind === "poweroff")
                    Session.poweroff();
                else if (kind === "reboot")
                    Session.reboot();
                else if (kind === "firmware")
                    Session.rebootToFirmware();
            }

            // what the menu shows, for the IPC `state` readout
            function describe() {
                const names = ["lock", "sleep", "hibernate", "logout", "restart", "shutdown", "taskmanager", "firmware"];
                const labelled = pending !== "" ? countdown.item.labelled : tiles.every(t => !t.visible || t.labelVisible);
                const tile = names[tiles.findIndex(t => t.activeFocus)] ?? "none";
                const focus = pending !== "" ? "countdown-" + countdown.item.focused : tile;
                const seconds = pending !== "" ? countdown.item.remaining : 0;
                return `pending=${pending} remaining=${seconds} focus=${focus} labelled=${labelled}`;
            }

            // arrows walk the tiles in reading order; up and down hop to the nearest tile in the other row
            function move(key) {
                const live = tiles.filter(t => t.visible);
                const at = live.findIndex(t => t.activeFocus);
                if (at < 0)
                    return false;
                const here = live[at];
                if (key === Qt.Key_Left || key === Qt.Key_Right) {
                    live[Math.max(0, Math.min(live.length - 1, at + (key === Qt.Key_Right ? 1 : -1)))].forceActiveFocus();
                    return true;
                }
                if (key !== Qt.Key_Up && key !== Qt.Key_Down)
                    return false;
                const inPrimary = here.parent === primaryRow;
                if (inPrimary === (key === Qt.Key_Up))
                    return true;
                const x = here.mapToItem(null, here.width / 2, 0).x;
                const other = live.filter(t => (t.parent === primaryRow) !== inPrimary);
                other.sort((l, r) => Math.abs(l.mapToItem(null, l.width / 2, 0).x - x) - Math.abs(r.mapToItem(null, r.width / 2, 0).x - x));
                other[0].forceActiveFocus();
                return true;
            }

            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:session"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            color: ColorUtils.transparentize(Appearance.m3colors.m3background, Appearance.m3colors.darkmode ? 0.05 : 0.12)

            anchors {
                top: true
                left: true
                right: true
            }

            implicitWidth: root.focusedScreen?.width ?? 0
            implicitHeight: root.focusedScreen?.height ?? 0

            MouseArea {
                id: sessionMouseArea
                anchors.fill: parent
                onClicked: sessionRoot.back()
            }

            ColumnLayout { // Content column
                id: contentColumn
                anchors.centerIn: parent
                spacing: 24

                Keys.onPressed: event => {
                    if (sessionRoot.pending !== "") {
                        event.accepted = countdown.item.handleKey(event);
                    } else if (event.key === Qt.Key_Escape) {
                        sessionRoot.hide();
                    } else if (sessionRoot.pending === "" && sessionRoot.move(event.key)) {
                        event.accepted = true;
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    horizontalAlignment: Text.AlignHCenter
                    visible: sessionRoot.pending === ""
                    font {
                        family: Appearance.font.family.title
                        pixelSize: Appearance.font.pixelSize.title
                        variableAxes: Appearance.font.variableAxes.title
                    }
                    text: Translation.tr("Session")
                }

                RowLayout {
                    id: primaryRow
                    Layout.alignment: Qt.AlignHCenter
                    visible: sessionRoot.pending === ""
                    spacing: 15

                    SessionActionButton {
                        id: sessionLock
                        buttonIcon: "lock"
                        buttonText: Translation.tr("Lock")
                        onClicked: {
                            Session.lock();
                            sessionRoot.hide();
                        }
                    }
                    SessionActionButton {
                        id: sessionSleep
                        buttonIcon: "dark_mode"
                        buttonText: Translation.tr("Sleep")
                        onClicked: {
                            Session.suspend();
                            sessionRoot.hide();
                        }
                    }
                    SessionActionButton {
                        id: sessionHibernate
                        // Without a resume device the button does nothing.
                        visible: SessionWarnings.canHibernate
                        buttonIcon: "downloading"
                        buttonText: Translation.tr("Hibernate")
                        onClicked: {
                            Session.hibernate();
                            sessionRoot.hide();
                        }
                    }
                    SessionActionButton {
                        id: sessionLogout
                        buttonIcon: "logout"
                        buttonText: Translation.tr("Log out")
                        onClicked: {
                            Session.logout();
                            sessionRoot.hide();
                        }
                    }
                    SessionActionButton {
                        id: sessionReboot
                        buttonIcon: "restart_alt"
                        buttonText: Translation.tr("Restart")
                        onClicked: sessionRoot.begin("reboot", sessionReboot)
                    }
                    SessionActionButton {
                        id: sessionShutdown
                        buttonIcon: "power_settings_new"
                        buttonText: Translation.tr("Shut down")
                        onClicked: sessionRoot.begin("poweroff", sessionShutdown)
                    }
                }

                RowLayout {
                    id: secondaryRow
                    Layout.alignment: Qt.AlignHCenter
                    visible: sessionRoot.pending === ""
                    spacing: 15

                    SessionActionButton {
                        id: sessionTaskManager
                        compact: true
                        buttonIcon: "browse_activity"
                        buttonText: Translation.tr("Task manager")
                        onClicked: {
                            Session.launchTaskManager();
                            sessionRoot.hide();
                        }
                    }
                    SessionActionButton {
                        id: sessionFirmwareReboot
                        compact: true
                        buttonIcon: "settings_applications"
                        buttonText: Translation.tr("Restart to firmware setup")
                        onClicked: sessionRoot.begin("firmware", sessionFirmwareReboot)
                    }
                }

                Loader {
                    id: countdown
                    Layout.alignment: Qt.AlignHCenter
                    active: sessionRoot.pending !== ""
                    onLoaded: item.takeFocus()
                    sourceComponent: SessionCountdown {
                        title: sessionRoot.texts[sessionRoot.pending].many
                        titleOne: sessionRoot.texts[sessionRoot.pending].one
                        nowText: sessionRoot.texts[sessionRoot.pending].now
                        onCancelled: sessionRoot.cancel()
                        onConfirmed: sessionRoot.commit()
                    }
                }
            }

            ColumnLayout {
                anchors {
                    top: contentColumn.bottom
                    topMargin: 10
                    horizontalCenter: contentColumn.horizontalCenter
                }
                spacing: 10

                Loader {
                    Layout.alignment: Qt.AlignHCenter
                    active: SessionWarnings.downloadRunning
                    visible: active
                    sourceComponent: DescriptionLabel {
                        text: Translation.tr("There might be a download in progress. Check your Downloads folder.")
                        textColor: Appearance.m3colors.m3onErrorContainer
                        color: Appearance.m3colors.m3errorContainer
                    }
                }

                Loader {
                    Layout.alignment: Qt.AlignHCenter
                    active: SessionWarnings.packageManagerRunning
                    visible: active
                    sourceComponent: DescriptionLabel {
                        text: Translation.tr("Your package manager is running")
                        textColor: Appearance.m3colors.m3onErrorContainer
                        color: Appearance.m3colors.m3errorContainer
                    }
                }
            }
        }
    }

    component DescriptionLabel: Rectangle {
        id: descriptionLabel
        property string text
        property color textColor: Appearance.colors.colOnTooltip
        color: Appearance.colors.colTooltip
        clip: true
        radius: Appearance.rounding.normal
        implicitHeight: descriptionLabelText.implicitHeight + 10 * 2
        implicitWidth: descriptionLabelText.implicitWidth + 15 * 2

        Behavior on implicitWidth {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        StyledText {
            id: descriptionLabelText
            anchors.centerIn: parent
            color: descriptionLabel.textColor
            text: descriptionLabel.text
        }
    }

    IpcHandler {
        target: "session"

        function toggle(): void {
            GlobalStates.sessionOpen = !GlobalStates.sessionOpen;
        }

        function close(): void {
            GlobalStates.sessionOpen = false;
        }

        function open(): void {
            GlobalStates.sessionOpen = true;
        }

        function state(): string {
            return surface.item ? surface.item.describe() : "closed";
        }
    }

    GlobalShortcut {
        name: "sessionToggle"
        description: "Toggles session screen on press"

        onPressed: {
            GlobalStates.sessionOpen = !GlobalStates.sessionOpen;
        }
    }

    GlobalShortcut {
        name: "sessionOpen"
        description: "Opens session screen on press"

        onPressed: {
            GlobalStates.sessionOpen = true;
        }
    }

    GlobalShortcut {
        name: "sessionClose"
        description: "Closes session screen on press"

        onPressed: {
            GlobalStates.sessionOpen = false;
        }
    }
}

pragma Singleton
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

/**
 * Keep awake: the idle inhibitor behind the sidebar switch, the bar indicator and `idle inhibit`.
 */
Singleton {
    id: root

    property alias inhibit: idleInhibitor.enabled
    inhibit: false

    // pid file: a restarted shell stops the inhibitor its predecessor left
    readonly property string inhibitorPidFile: `${Quickshell.env("XDG_RUNTIME_DIR")}/koompi-keep-awake.pid`
    // [q]: the wrapper's own cmdline carries this text and must not match it
    readonly property string inhibitorPattern: "who=[q]uickshell --why=Keep system awake"

    onInhibitChanged: {
        if (!root.inhibit) root.stopInhibitor();
    }

    // restore the saved switch and stop a predecessor's inhibitor; a states.json that loads before
    // this singleton exists (every machine that has run the shell) fires no readyChanged here
    function restore() {
        if (!Persistent.isNewHyprlandInstance) {
            root.inhibit = Persistent.states.idle.inhibit;
        } else {
            Persistent.states.idle.inhibit = root.inhibit;
        }
        if (!root.inhibit) root.stopInhibitor();
    }

    Component.onCompleted: if (Persistent.ready) root.restore()

    Connections {
        target: Persistent
        function onReadyChanged() {
            if (Persistent.ready) root.restore();
        }
    }

    function toggleInhibit(active = null) {
        if (active !== null) {
            root.inhibit = active;
        } else {
            root.inhibit = !root.inhibit;
        }
        Persistent.states.idle.inhibit = root.inhibit;
    }

    // `qs -c koompi ipc call idle inhibit on|off|toggle|status`. Every verb
    // answers with the resulting state as the literal on/off, so koompi-toggle
    // (and anything scripted on it) can exit on the word without a second call.
    IpcHandler {
        target: "idle"

        function inhibit(verb: string): string {
            if (verb === "on") root.toggleInhibit(true);
            else if (verb === "off") root.toggleInhibit(false);
            else if (verb === "toggle") root.toggleInhibit();
            else if (verb !== "status") return "usage: inhibit on|off|toggle|status";
            return root.inhibit ? "on" : "off";
        }
    }

    // a recorded pid may have been reused: kill it only while its cmdline still matches
    readonly property string stopInhibitorScript: `pid=$(cat "$1" 2>/dev/null); [[ $pid =~ ^[0-9]+$ ]] && tr '\\0' ' ' 2>/dev/null < "/proc/$pid/cmdline" | grep -qE "$2" && kill "$pid"; rm -f "$1"`

    function stopInhibitor() {
        Quickshell.execDetached(["bash", "-c", root.stopInhibitorScript, "bash", root.inhibitorPidFile, root.inhibitorPattern]);
    }

    // The Wayland inhibitor below only works while its surface is mapped, which
    // is unreliable on Hyprland (the 1x1 window often never maps). Back it with a
    // systemd idle inhibitor, which hypridle honors directly.
    //
    // handle-lid-switch is separate on purpose: logind weighs the lid against that
    // class alone, so a blocked idle:sleep still suspended the moment the lid shut.
    Process {
        running: root.inhibit
        command: ["bash", "-c",
            `${root.stopInhibitorScript}; echo $$ > "$1"; exec systemd-inhibit --what=idle:sleep:handle-lid-switch --mode=block --who=quickshell --why='Keep system awake' sleep infinity`,
            "bash", root.inhibitorPidFile, root.inhibitorPattern]
    }

    IdleInhibitor {
        id: idleInhibitor
        window: PanelWindow {
            // Inhibitor only works while its surface is actually mapped.
            // A 0x0 window never maps, so Hyprland ignores the inhibitor.
            visible: idleInhibitor.enabled
            implicitWidth: 1
            implicitHeight: 1
            color: "transparent"
            // Just in case...
            anchors {
                right: true
                bottom: true
            }
            // Make it not interactable
            mask: Region {
                item: null
            }
        }
    }
}

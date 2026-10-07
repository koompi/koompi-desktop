import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
pragma Singleton
pragma ComponentBehavior: Bound

/**
 * Whether EasyEffects is installed and running, and the sidebar toggle that
 * starts and stops it. The toggle's last state is kept in states.json, and
 * login starts it unless the user turned it off.
 */
Singleton {
    id: root

    property bool available: false
    property bool active: false
    property bool _availabilityKnown: false
    property bool _activeKnown: false
    property bool _restored: false

    function load() {}

    function fetchAvailability() {
        fetchAvailabilityProc.running = true
    }

    function fetchActiveState() {
        fetchActiveStateProc.running = true
    }

    function disable() {
        root.active = false
        Persistent.states.easyEffects.enabled = false
        Quickshell.execDetached(["bash", "-c", "pkill easyeffects || flatpak pkill com.github.wwmm.easyeffects"])
        settleTimer.restart()
    }

    function enable() {
        root.active = true
        Persistent.states.easyEffects.enabled = true
        Quickshell.execDetached(["bash", "-c", "easyeffects --hide-window --service-mode || flatpak run com.github.wwmm.easyeffects --hide-window --service-mode"])
        settleTimer.restart()
    }

    // the remembered toggle is read once, after the states file and both probes have answered
    function _restoreOnce() {
        if (root._restored || !Persistent.ready || !root._availabilityKnown || !root._activeKnown) return
        root._restored = true
        if (Persistent.states.easyEffects.enabled && root.available && !root.active) root.enable()
    }

    Connections {
        target: Persistent
        function onReadyChanged() {
            root._restoreOnce()
        }
    }

    // launch/kill is detached and can fail; read the real state back
    Timer {
        id: settleTimer
        interval: 1000
        repeat: false
        onTriggered: root.fetchActiveState()
    }

    function toggle() {
        if (root.active) {
            root.disable()
        } else {
            root.enable()
        }
    }

    Process {
        id: fetchAvailabilityProc
        running: true
        command: ["bash", "-c", "command -v easyeffects || flatpak info com.github.wwmm.easyeffects > /dev/null 2>&1"]
        onExited: (exitCode, exitStatus) => {
            root.available = exitCode === 0
            root._availabilityKnown = true
            root._restoreOnce()
        }
    }

    Process {
        id: fetchActiveStateProc
        running: true
        command: ["bash", "-c", "pidof easyeffects || flatpak ps | grep com.github.wwmm.easyeffects > /dev/null 2>&1"]
        onExited: (exitCode, exitStatus) => {
            root.active = exitCode === 0
            root._activeKnown = true
            root._restoreOnce()
        }
    }
}

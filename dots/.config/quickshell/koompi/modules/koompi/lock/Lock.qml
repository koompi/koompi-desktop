pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.panels.lock
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

LockScreen {
    id: root

    lockSurface: LockSurface {
        context: root.context
    }

    // Monitor name -> workspace id to restore on unlock. Only monitors this
    // actually moved get an entry, so a monitor that was never pushed is never
    // "restored" to a workspace it was not on.
    property var savedWorkspaces: ({})

    function activeWorkspaceIdFor(screen) {
        // The live Hyprland object first; HyprlandData is a polled cache and is
        // briefly empty after a hot-plug or a compositor restart.
        const live = Hyprland.monitorFor(screen)?.activeWorkspace?.id;
        if (live !== undefined && live !== null)
            return live;
        const cached = HyprlandData.monitors?.find(m => m.name === screen.name)?.activeWorkspace?.id;
        return (cached !== undefined && cached !== null) ? cached : null;
    }

    // Move each monitor to a workspace far outside the usable range, so the
    // desktop is not sitting behind the lock surface waiting to be revealed by
    // a compositor bug. A monitor whose workspace is not known yet is skipped
    // and retried; it must not cost every other monitor its push.
    function pushMonitorsAway(screens) {
        var batch = "";
        var pending = [];
        var saved = root.savedWorkspaces;
        for (var i = 0; i < screens.length; ++i) {
            var screen = screens[i];
            if (saved[screen.name] !== undefined)
                continue;
            var workspaceId = root.activeWorkspaceIdFor(screen);
            if (workspaceId === null) {
                pending.push(screen);
                continue;
            }
            // already pushed away (a shell restarted under the lock): remember where it came from
            if (workspaceId > 2147483647 - 1000) {
                saved[screen.name] = 2147483647 - workspaceId;
                continue;
            }
            saved[screen.name] = workspaceId;
            batch += `hyprctl dispatch 'hl.dsp.focus({monitor="${screen.name}"})'; hyprctl dispatch 'hl.dsp.focus({workspace=${2147483647 - workspaceId}})';`;
        }
        root.savedWorkspaces = saved;
        if (batch.length > 0)
            Quickshell.execDetached(["bash", "-c", batch]);
        return pending;
    }

    property var pendingScreens: []

    // The lock outlives this process. While locked, the lock and where each monitor came from
    // are kept in the runtime directory, tagged with this Hyprland instance. A shell that
    // starts and finds them (it crashed, or something restarted it under the lock) locks
    // again at once - allow_session_lock_restore lets it take over - instead of leaving the
    // seat on Hyprland's "lockscreen app died" screen, and still puts the desktop back on
    // unlock. An update that finds the session locked leaves restartPending, and the shell
    // restarts itself after the unlock instead.
    readonly property string runtimeDir: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/koompi`
    readonly property string lockStatePath: `${root.runtimeDir}/lock-state.json`
    readonly property string restartPendingPath: `${root.runtimeDir}/shell-restart-pending`
    readonly property string instance: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ?? ""
    onSavedWorkspacesChanged: persistTimer.restart()
    // one write for a burst of changes, so a stale write can never land after a newer one
    Timer {
        id: persistTimer
        interval: 100
        onTriggered: {
            if (GlobalStates.screenLocked)
                Quickshell.execDetached(["bash", "-c", 'mkdir -p "$1" && printf "%s" "$2" > "$3.tmp" && mv "$3.tmp" "$3"', "_",
                    root.runtimeDir, JSON.stringify({
                        "instance": root.instance,
                        "workspaces": root.savedWorkspaces
                    }), root.lockStatePath]);
            else
                Quickshell.execDetached(["rm", "-f", root.lockStatePath]);
        }
    }
    Process {
        id: lockStateReader
        command: ["cat", root.lockStatePath]
        stdout: StdioCollector {
            onStreamFinished: {
                let state = null;
                try {
                    state = JSON.parse(text);
                } catch (e) {
                    return;
                }
                if (!state || state.instance !== root.instance || root.instance.length === 0 || GlobalStates.screenLocked)
                    return;
                GlobalStates.screenLocked = true;
                root.savedWorkspaces = state.workspaces ?? ({});
            }
        }
    }
    Component.onCompleted: lockStateReader.running = true
    // The restart an update deferred. Detached, because koompi-reload stops this process; the
    // pause lets logind's LockedHint clear first, or koompi-reload refuses.
    function runDeferredRestart() {
        Quickshell.execDetached(["bash", "-c", '[ -e "$1" ] || exit 0; rm -f "$1"; sleep 2; PATH="$HOME/.local/bin:$PATH" exec koompi-reload',
            "_", root.restartPendingPath]);
    }

    // Moving every monitor to another workspace is an animated workspace switch
    // as far as the compositor is concerned. Held back until the lock surface is
    // up so that switch plays behind it, instead of being the last thing on
    // screen before the lock covers it.
    Timer {
        id: pushDelayTimer
        interval: 250
        onTriggered: {
            if (!GlobalStates.screenLocked)
                return;
            root.pendingScreens = root.pushMonitorsAway(Quickshell.screens);
            if (root.pendingScreens.length > 0) {
                pushRetryTimer.attemptsLeft = 5;
                pushRetryTimer.restart();
            }
        }
    }

    Timer {
        id: pushRetryTimer
        interval: 200
        repeat: true
        property int attemptsLeft: 0
        onTriggered: {
            root.pendingScreens = root.pushMonitorsAway(root.pendingScreens);
            attemptsLeft -= 1;
            if (root.pendingScreens.length === 0 || attemptsLeft <= 0)
                stop();
        }
    }

    // Clearing savedWorkspaces makes this idempotent, so calling it twice costs
    // nothing and the second caller is a safety net rather than a second move.
    function restoreMonitors() {
        // An unlock faster than the delay must cancel the push outright, or the
        // monitors get moved away after they were put back.
        pushDelayTimer.stop();
        pushRetryTimer.stop();
        root.pendingScreens = [];
        var batch = "";
        for (var i = 0; i < Quickshell.screens.length; ++i) {
            var name = Quickshell.screens[i].name;
            var workspaceId = root.savedWorkspaces[name];
            if (workspaceId === undefined)
                continue;
            batch += `hyprctl dispatch 'hl.dsp.focus({monitor="${name}"})'; hyprctl dispatch 'hl.dsp.focus({workspace=${workspaceId}})';`;
        }
        root.savedWorkspaces = ({});
        if (batch.length > 0)
            Quickshell.execDetached(["bash", "-c", batch]);
    }

    // The password has been accepted but the surface is still up, which is the
    // only moment the desktop can be put back without the move being watched.
    onAboutToUnlock: root.restoreMonitors()

    // One batch for lock and one for unlock, so multiple hyprctl calls cannot
    // race each other into the wrong workspace.
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked) {
                pushRetryTimer.stop();
                root.savedWorkspaces = ({});
                // Read which wallpaper each monitor is showing BEFORE moving
                // any of them, in the same handler, so no other connection can
                // run in between and read the pushed-away workspace instead.
                root.context.clearCapturedWallpapers();
                root.context.captureWallpapers(Quickshell.screens);
                pushDelayTimer.restart();
            } else {
                // Anything that clears the flag without going through the
                // unlock path still gets its workspaces back.
                root.restoreMonitors();
                root.runDeferredRestart();
            }
            persistTimer.restart();
        }
    }

    // A monitor plugged in while locked has no saved workspace, so it is pushed
    // now and restored with the rest.
    Connections {
        target: Quickshell
        function onScreensChanged() {
            if (!GlobalStates.screenLocked)
                return;
            root.context.captureWallpapers(Quickshell.screens);
            root.pendingScreens = root.pushMonitorsAway(Quickshell.screens);
            root.context.shouldReFocus();
        }
    }
}

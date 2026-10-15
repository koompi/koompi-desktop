pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// The single data owner for every monitor's global-menu renderer. Keeping the
// daemon here is important: com.canonical.AppMenu.Registrar has one owner, and
// applications must not have to register again when focus changes monitors.
Singleton {
    id: root

    // first one present wins: ./setup installs into ~/.local/bin (sdata/install/setups/globalmenu.sh),
    // the koompi-shell package into /usr/lib/koompi; one basename, so a restart stops either by name
    readonly property var daemonCandidates: [Quickshell.env("HOME") + "/.local/bin/koompi-global-menu-daemon", "/usr/lib/koompi/koompi-global-menu-daemon"]

    property var menuItems: []
    // Lazy submenu contents keyed by the stable daemon item id.
    property var patchedChildren: ({})
    // The id space menuItems belongs to. Item ids are handed out per payload and
    // reused, so the daemon stamps every payload with one and refuses any
    // command carrying a generation it has already replaced. Zero means nothing
    // has arrived yet, which the daemon never issues.
    property int generation: 0

    // Renderers use this to close local popup state before adopting a new
    // focused application's menu tree.
    signal menuReset()

    function send(command) {
        if (daemon.running)
            daemon.write(command + "\n");
    }

    /// Sends a command that names an item id. The generation the id came from
    /// goes with it, so a click the user made just before focus moved cannot
    /// land on the menu that replaced it.
    function sendForItem(command) {
        root.send(command + " " + root.generation);
    }

    function childrenOf(entry) {
        if (!entry)
            return [];
        const patched = root.patchedChildren[entry.id];
        return patched ?? entry.items ?? [];
    }

    function hasChildrenFor(entry) {
        if (!entry)
            return false;
        return entry.sub === true || root.childrenOf(entry).length > 0;
    }

    Process {
        id: daemon
        command: ["bash", "-c", 'for bin; do if [ -x "$bin" ]; then exec "$bin"; fi; done; exit 127', "bash", ...root.daemonCandidates]
        running: true
        stdinEnabled: true

        stdout: SplitParser {
            onRead: line => {
                let payload;
                try {
                    payload = JSON.parse(line);
                } catch (e) {
                    return;
                }
                if (payload.patch !== undefined) {
                    // A patch extends the payload it was requested for. If the
                    // menu has been replaced since, its ids mean nothing here.
                    if (payload.gen !== root.generation)
                        return;
                    const next = Object.assign({}, root.patchedChildren);
                    next[payload.patch] = payload.items ?? [];
                    root.patchedChildren = next;
                    return;
                }
                root.menuReset();
                root.patchedChildren = ({});
                // Adopt the new id space before the items that live in it, so
                // nothing reacting to menuItems can send against the old one.
                root.generation = payload.gen ?? 0;
                root.menuItems = payload.items ?? [];
            }
        }

        onRunningChanged: {
            if (!running) {
                root.menuReset();
                root.patchedChildren = ({});
                root.generation = 0;
                root.menuItems = [];
            }
        }

        onExited: (exitCode, exitStatus) => {
            // 127: none installed, which a retry cannot change; the next shell start looks again
            if (exitCode === 127) {
                console.warn("[GlobalMenuService] no global menu daemon in", root.daemonCandidates.join(", "), "- the bar shows no app menus");
                return;
            }
            restartTimer.start();
        }
    }

    Timer {
        id: restartTimer
        interval: 3000
        onTriggered: daemon.running = true
    }
}

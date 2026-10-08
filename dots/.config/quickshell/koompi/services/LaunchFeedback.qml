pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "launch-match.js" as LaunchMatch

// apps asked to start that have shown no window yet
Singleton {
    id: root

    property int ttl: 8000
    property var pending: []
    readonly property var current: root.pending.length > 0 ? root.pending[root.pending.length - 1] : null

    // heuristicLookup("") answers with an arbitrary entry
    function entryOf(windowClass) {
        if (!windowClass)
            return "";
        return DesktopEntries.heuristicLookup(windowClass)?.id ?? "";
    }

    function add(spec) {
        const launch = LaunchMatch.record(spec, HyprlandData.windowList, HyprlandData.activeWindow, Date.now());
        root.pending = [...root.pending.slice(-7), launch];
    }

    function begin(entry) {
        if (!entry)
            return;
        root.add({
            id: entry.id,
            entryId: entry.id,
            name: entry.name,
            icon: entry.icon,
            startupClass: entry.startupClass,
            program: LaunchMatch.programOf(entry.command?.[0])
        });
    }

    function resolve(launchId, program) {
        return DesktopEntries.byId(launchId)
            ?? LaunchMatch.entryForProgram(program, DesktopEntries.applications.values)
            ?? (program ? DesktopEntries.heuristicLookup(program) : null);
    }

    function sweep() {
        const waiting = LaunchMatch.settle(root.pending, HyprlandData.windowList, HyprlandData.activeWindow, root.entryOf, Date.now(), root.ttl);
        if (waiting.length !== root.pending.length)
            root.pending = waiting;
    }

    Connections {
        target: HyprlandData
        function onWindowListChanged() {
            root.sweep();
        }
    }

    Timer {
        interval: 250
        repeat: true
        running: root.pending.length > 0
        onTriggered: root.sweep()
    }

    // koompi-launch calls begin for a key bind
    IpcHandler {
        target: "launch"

        function begin(launchId: string, program: string, pid: int): string {
            const entry = root.resolve(launchId, program);
            if (!entry || LaunchMatch.pidMapped(pid, HyprlandData.windowList))
                return "ignored";
            root.add({
                id: launchId,
                entryId: entry.id,
                name: entry.name,
                icon: entry.icon,
                startupClass: entry.startupClass,
                program: program,
                pid: pid
            });
            return "ok";
        }

        function status(): string {
            return root.current?.name ?? "";
        }
    }
}

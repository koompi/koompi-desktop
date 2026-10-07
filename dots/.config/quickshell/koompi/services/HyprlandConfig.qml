pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

import qs.modules.common
import qs.modules.common.functions

/**
 * Configs Hyprland
 */
Singleton {
    id: root

    signal reloaded()
    // every run asked for has ended, and at least one of them failed
    signal writeFailed()

    readonly property string configuratorScriptPath: Quickshell.shellPath("scripts/hyprland/hyprconfigurator.py")
    readonly property string shellOverridesPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/hyprland/shellOverrides/main.lua`)

    property int timeoutMs: 10000
    property var pendingSets: ({})
    property var pendingResets: ({})
    property bool failedSinceDrain: false
    property bool exited: false
    property bool stderrEnded: false
    property int exitCode: 0

    // the script rewrites the whole file: one run at a time, asks made during a run merge into the next
    function apply(sets: var, resets: var) {
        for (const key in sets) {
            root.pendingSets[key] = sets[key];
            delete root.pendingResets[key];
        }
        for (const key of resets) {
            delete root.pendingSets[key];
            root.pendingResets[key] = true;
        }
        root.next();
    }

    function set(key: string, value: var) {
        root.apply({ [key]: value }, []);
    }

    function setMany(entries: var) {
        root.apply(entries, []);
    }

    function reset(key: string) {
        root.apply({}, [key]);
    }

    function resetMany(keys: list<string>) {
        root.apply({}, keys);
    }

    function next() {
        if (runner.running)
            return;
        const argv = [root.configuratorScriptPath, "--file", root.shellOverridesPath];
        for (const key in root.pendingSets)
            argv.push("--set", key, String(root.pendingSets[key]));
        for (const key in root.pendingResets)
            argv.push("--reset", key);
        root.pendingSets = {};
        root.pendingResets = {};
        if (argv.length === 3) {
            if (root.failedSinceDrain) {
                root.failedSinceDrain = false;
                root.writeFailed();
            }
            return;
        }
        root.exited = false;
        root.stderrEnded = false;
        runner.exec(argv);
    }

    // exit status and stderr arrive separately, in either order
    function settle() {
        if (!root.exited || !root.stderrEnded)
            return;
        if (root.exitCode !== 0) {
            console.warn(`[HyprlandConfig] ${runner.command.join(" ")} exited ${root.exitCode}: ${errors.text.trim()}`);
            root.failedSinceDrain = true;
        }
        Qt.callLater(root.next);
    }

    Process {
        id: runner

        stderr: StdioCollector {
            id: errors
            onStreamFinished: {
                root.stderrEnded = true;
                root.settle();
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.exitCode = exitStatus === 0 ? exitCode : -1;
            root.exited = true;
            root.settle();
        }
        onRunningChanged: {
            if (runner.running || root.exited)
                return;
            console.warn(`[HyprlandConfig] ${runner.command.join(" ")} did not start`);
            root.failedSinceDrain = true;
            Qt.callLater(root.next);
        }
    }

    Timer {
        interval: root.timeoutMs
        running: runner.running
        onTriggered: {
            console.warn(`[HyprlandConfig] ${runner.command.join(" ")} still running after ${root.timeoutMs} ms, stopping it`);
            runner.running = false;
        }
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name == "configreloaded") {
                root.reloaded()
            }
        }
    }
}

pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    // property string cliphistBinary: FileUtils.trimFileProtocol(`${Directories.home}/.cargo/bin/stash`)
    property string cliphistBinary: "cliphist"
    property real pasteDelay: 0.05
    property string pressPasteCommand: "ydotool key -d 1 29:1 47:1 47:0 29:0"
    property bool sloppySearch: Config.options?.search.sloppy ?? false
    property real scoreThreshold: 0.2
    property list<string> entries: []
    readonly property var preparedEntries: entries.map(a => ({
        name: Fuzzy.prepare(`${a.replace(/^\s*\S+\s+/, "")}`),
        entry: a
    }))

    property bool _stale: true
    property bool _listed: false
    property string _configuredDbPath: ""
    readonly property string _dbPath: _configuredDbPath || FileUtils.trimFileProtocol(`${Directories.genericCache}/cliphist/db`)
    // what reads entries: the search list, and Ctrl+V in the chat composer and the wallpaper picker
    readonly property bool watching: GlobalStates.searchOpen || GlobalStates.sidebarLeftOpen || GlobalStates.wallpaperSelectorOpen
    onWatchingChanged: if (watching && _stale) refresh()

    function _dbPathFrom(config: string): string {
        let path = "";
        for (const line of config.split("\n")) {
            const match = /^\s*db-path\s+(.+?)\s*$/.exec(line);
            if (match) path = match[1];
        }
        return path;
    }

    function fuzzyQuery(search: string): var {
        if (search.trim() === "") {
            return entries;
        }
        if (root.sloppySearch) {
            const results = entries.slice(0, 100).map(str => ({
                entry: str,
                score: Levendist.computeTextMatchScore(str.toLowerCase(), search.toLowerCase())
            })).filter(item => item.score > root.scoreThreshold)
                .sort((a, b) => b.score - a.score)
            return results
                .map(item => item.entry)
        }

        return Fuzzy.go(search, preparedEntries, {
            all: true,
            key: "name"
        }).map(r => {
            return r.obj.entry
        });
    }

    function entryIsImage(entry) {
        return !!(/^\d+\t\[\[.*binary data.*\d+x\d+.*\]\]$/.test(entry))
    }

    function refresh() {
        if (readProc.running) {
            readProc.rerun = true
            return
        }
        root._stale = false
        readProc.buffer = []
        readProc.running = true
    }

    function copy(entry) {
        if (root.cliphistBinary.includes("cliphist")) // Classic cliphist
            Quickshell.execDetached(["bash", "-c", `printf '${StringUtils.shellSingleQuoteEscape(entry)}' | ${root.cliphistBinary} decode | wl-copy`]);
        else { // Stash
            const entryNumber = entry.split("\t")[0];
            Quickshell.execDetached(["bash", "-c", `${root.cliphistBinary} decode ${entryNumber} | wl-copy`]);
        }
    }

    function paste(entry) {
        if (root.cliphistBinary.includes("cliphist")) // Classic cliphist
            Quickshell.execDetached(["bash", "-c", `printf '${StringUtils.shellSingleQuoteEscape(entry)}' | ${root.cliphistBinary} decode | wl-copy && wl-paste`]);
        else { // Stash
            const entryNumber = entry.split("\t")[0];
            Quickshell.execDetached(["bash", "-c", `${root.cliphistBinary} decode ${entryNumber} | wl-copy; ${root.pressPasteCommand}`]);
        }
    }

    function superpaste(count, isImage = false) {
        // Find entries
        const targetEntries = entries.filter(entry => {
            if (!isImage) return true;
            return entryIsImage(entry);
        }).slice(0, count)
        const pasteCommands = [...targetEntries].reverse().map(entry => `printf '${StringUtils.shellSingleQuoteEscape(entry)}' | ${root.cliphistBinary} decode | wl-copy && sleep ${root.pasteDelay} && ${root.pressPasteCommand}`)
        // Act
        Quickshell.execDetached(["bash", "-c", pasteCommands.join(` && sleep ${root.pasteDelay} && `)]);
    }

    Process {
        id: deleteProc
        // starts on the event loop and a start while running is dropped: queue, argv built at exec()
        property list<string> pending: []
        property bool busy: false
        function deleteEntry(entry) {
            deleteProc.pending = [...deleteProc.pending, entry];
            deleteProc.next();
        }
        function next() {
            if (deleteProc.busy || deleteProc.pending.length === 0) return;
            deleteProc.busy = true;
            const entry = deleteProc.pending[0];
            deleteProc.pending = deleteProc.pending.slice(1);
            deleteProc.exec(["bash", "-c", `echo '${StringUtils.shellSingleQuoteEscape(entry)}' | ${root.cliphistBinary} delete`]);
        }
        onExited: (exitCode, exitStatus) => {
            deleteProc.busy = false;
            if (exitCode !== 0) console.error("[Cliphist] Failed to delete entry with code", exitCode, "and status", exitStatus);
            if (deleteProc.pending.length > 0) deleteProc.next();
            else root.refresh();
        }
    }

    function deleteEntry(entry) {
        deleteProc.deleteEntry(entry);
    }

    Process {
        id: wipeProc
        command: [root.cliphistBinary, "wipe"]
        onExited: (exitCode, exitStatus) => {
            root.refresh();
        }
    }

    function wipe() {
        wipeProc.running = true;
    }

    Connections {
        target: Quickshell
        function onClipboardTextChanged() {
            changedTimer.restart()
        }
    }

    Timer {
        id: changedTimer
        interval: 200
        onTriggered: {
            root._stale = true
            if (root.watching) root.refresh()
        }
    }

    FileView {
        id: cliphistConfig
        path: FileUtils.trimFileProtocol(`${Directories.config}/cliphist/config`)
        printErrors: false
        onLoaded: root._configuredDbPath = root._dbPathFrom(cliphistConfig.text())
    }

    FileView {
        // cliphist makes its cache dir on first run, and a watch cannot arm in a dir that is missing
        path: root._listed ? root._dbPath : ""
        preload: false
        watchChanges: true
        onFileChanged: changedTimer.restart()
    }

    Process {
        id: readProc
        property list<string> buffer: []
        property bool rerun: false

        command: [root.cliphistBinary, "list"]

        stdout: SplitParser {
            onRead: (line) => {
                readProc.buffer.push(line)
            }
        }

        onExited: (exitCode, exitStatus) => {
            root._listed = true
            if (exitCode === 0) {
                root.entries = readProc.buffer
            } else {
                console.error("[Cliphist] Failed to refresh with code", exitCode, "and status", exitStatus)
                root._stale = true
            }
            if (readProc.rerun) {
                readProc.rerun = false
                root.refresh()
            }
        }
    }

    IpcHandler {
        target: "cliphistService"

        function update(): void {
            root.refresh()
        }
    }
}

pragma Singleton

import "launcherSearch/file-format.js" as FileFormat
import qs
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * - Recent documents, read from the XDG list every desktop app already writes
 * - On-demand filename search under $HOME via fd
 */
Singleton {
    id: root

    property string query: ""
    property list<var> recents: []
    property list<var> files: []

    readonly property var preparedRecents: recents.map(entry => ({
        name: Fuzzy.prepare(entry.name),
        entry: entry
    }))

    // Filenames are long, and subsequence matching will find "README" inside
    // almost any of them, so this scope needs a floor the app list does not.
    readonly property real scoreThreshold: 0.5

    function fuzzyRecents(search: string): var {
        if (search.trim() === "")
            return recents.slice(0, 20);
        return Fuzzy.go(search, preparedRecents, {
            all: true,
            key: "name",
            threshold: root.scoreThreshold,
            limit: 20
        }).map(r => r.obj.entry);
    }

    function displayPath(path) {
        const home = FileUtils.trimFileProtocol(Directories.home);
        return path.startsWith(home + "/") ? "~" + path.slice(home.length) : path;
    }

    // The path whose Quick Look is up, "" when none is. koompi-quicklook toggles,
    // so a second Space on the same file takes it down again.
    property string quicklookPath: ""

    function toggleQuicklook(path) {
        Quickshell.execDetached(["koompi-quicklook", path]);
        root.quicklookPath = root.quicklookPath === path ? "" : path;
    }

    function closeQuicklook(): bool {
        if (root.quicklookPath === "")
            return false;
        root.quicklookPath = "";
        Quickshell.execDetached(["koompi-quicklook", "close"]);
        return true;
    }

    Connections {
        target: GlobalStates
        function onSearchOpenChanged() {
            if (!GlobalStates.searchOpen)
                root.closeQuicklook();
        }
    }

    function open(path) {
        Quickshell.execDetached(["xdg-open", path]);
    }

    function revealParent(path) {
        Quickshell.execDetached(["xdg-open", path.slice(0, path.lastIndexOf("/")) || "/"]);
    }

    onQueryChanged: findDebounce.restart()

    // Debian ships fd as `fdfind`; everywhere else it is `fd`. Resolved once.
    property string findBinary: ""

    Process {
        running: true
        command: ["bash", "-c", "command -v fd || command -v fdfind"]
        stdout: StdioCollector {
            onStreamFinished: root.findBinary = text.trim().split("\n")[0] ?? ""
        }
    }

    Timer {
        id: findDebounce
        interval: 250
        onTriggered: {
            const search = root.query.trim();
            if (search.length < 2 || root.findBinary === "") {
                root.files = [];
                return;
            }
            findProc.running = false;
            // The query is an argv entry, never a shell word, and --fixed-strings
            // keeps it out of fd's regex engine too.
            // fd matches basenames; a query with a separator in it is someone
            // typing a path, so match the whole path instead.
            // one pipeline: fd's first 30 hits go to a single stat, so the dates cost no process per row
            const pathArgs = search.includes("/") ? ["--full-path"] : [];
            const find = [root.findBinary, "--fixed-strings", "--hidden", "--type", "f", "--exclude", ".git", "--exclude", ".cache", "--exclude", "node_modules", ...pathArgs, search, FileUtils.trimFileProtocol(Directories.home)];
            findProc.command = ["bash", "-c", '"$@" | head -n 30 | tr "\\n" "\\0" | xargs -0 -r stat --printf "%Y\\t%n\\n" --', "fd-stat", ...find];
            findProc.running = true;
        }
    }

    Process {
        id: findProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.files = FileFormat.parseStat(text);
            }
        }
    }

    // ponytail: regex over the XBEL instead of an XML parser. The file is a flat
    // list of <bookmark> tags with no nesting, so there is nothing to walk.
    function parseXbel(xml) {
        const entries = [];
        const tagPattern = /<bookmark\b[^>]*>/g;
        let match;
        while ((match = tagPattern.exec(xml)) !== null) {
            const tag = match[0];
            const href = /href="([^"]*)"/.exec(tag)?.[1];
            if (!href?.startsWith("file://"))
                continue;
            const path = decodeURIComponent(href.slice("file://".length));
            entries.push({
                path: path,
                name: path.slice(path.lastIndexOf("/") + 1),
                modified: /modified="([^"]*)"/.exec(tag)?.[1] ?? ""
            });
        }
        // ISO 8601 timestamps, so lexical order is chronological order.
        entries.sort((a, b) => b.modified.localeCompare(a.modified));
        return entries;
    }

    FileView {
        id: recentFile
        // ponytail: deleted files stay in the list. Filtering needs a stat per
        // entry; add it if stale hits become a real complaint.
        path: FileUtils.trimFileProtocol(`${Directories.home}/.local/share/recently-used.xbel`)
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.recents = root.parseXbel(recentFile.text())
        onLoadFailed: root.recents = []
    }
}

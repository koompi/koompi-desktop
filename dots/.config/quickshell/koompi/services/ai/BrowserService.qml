pragma ComponentBehavior: Bound

import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * The agent's own browser for one AI session: one scripts/ai/browser.py, started by
 * the first request and closed by a new chat, the stop key or the shell exiting
 * (its stdin closes and it takes Chrome down). One JSON request per line in, one
 * reply per line out, routed back to its caller by id. `engine` is the Ai facade.
 *
 * KOOMPI_AI_BROWSER_HEADLESS=1 runs Chrome headless, for tests through headless.sh.
 */
QtObject {
    id: root

    property QtObject engine

    readonly property bool running: proc.running
    property int inFlight: 0
    // Chrome's process id, from the replies; the indicator matches the focused window against it
    property int pid: 0
    // ref number -> what the last snapshot said it is (`button "Pay" (submits form)`).
    // The driver sends these as data beside the text, so a page cannot forge one.
    property var refs: ({})
    property string title: ""
    property string url: ""
    property double lastReplyAt: 0
    // The user took the browser over: every step waits for them until they resume.
    property bool paused: false

    property int _nextId: 0
    property var _waiting: ({})
    property var _unsent: []
    property string _stopReason: ""

    readonly property bool headless: Quickshell.env("KOOMPI_AI_BROWSER_HEADLESS") === "1"
    readonly property string driverPath: `${Directories.scriptPath}/ai/browser.py`.replace(/file:\/\//, "")

    function request(op: string, fields: var, callback) {
        const id = ++root._nextId;
        root._waiting[id] = { "op": op, "callback": callback };
        root.inFlight++;
        const line = JSON.stringify(Object.assign({}, fields, { "id": id, "op": op })) + "\n";
        if (proc.running) {
            proc.write(line);
            return;
        }
        // written once the process is up; a write before that has nowhere to go
        root._unsent = [...root._unsent, line];
        root._stopReason = "";
        proc.running = true;
    }

    // SIGTERM: browser.py closes Chrome on its way out, mid-step or not. Whoever is
    // waiting is answered once the process has gone, with `reason`.
    function stop(reason: string) {
        root._unsent = [];
        if (!proc.running) {
            for (const id of Object.keys(root._waiting)) root.answer(id, { "ok": false, "error": reason });
            return;
        }
        root._stopReason = reason;
        proc.running = false;
    }

    // Mirrors the driver's own refs: a snapshot replaces them, and the ops that move to
    // another document or tab drop them, as browser.py does.
    function remember(op: string, reply) {
        if (Number.isInteger(reply.pid) && reply.pid > 0) root.pid = reply.pid;
        if (reply.refs) root.refs = reply.refs;
        else if (!reply.ok) return;
        else if (["back", "switch_tab", "close"].includes(op) || /opened a new tab/.test(reply.text ?? "")) root.refs = ({});
        if (reply.title !== undefined) root.title = reply.title;
        if (reply.url !== undefined) root.url = reply.url;
    }

    function answer(id, reply) {
        const waiting = root._waiting[id];
        if (!waiting) return;
        delete root._waiting[id];
        root.inFlight = Math.max(0, root.inFlight - 1);
        root.lastReplyAt = Date.now();
        root.remember(waiting.op, reply);
        waiting.callback(reply);
    }

    readonly property Process proc: Process {
        stdinEnabled: true
        command: ["python3", "-I", root.driverPath].concat(root.headless ? ["--headless"] : [])
        stdout: SplitParser {
            onRead: line => {
                let reply;
                try {
                    reply = JSON.parse(line);
                } catch (e) {
                    console.warn(`[Ai:browser] not a reply: ${line.slice(0, 200)}`);
                    return;
                }
                root.answer(reply.id, reply);
            }
        }
        stderr: SplitParser {
            onRead: data => console.warn("[Ai:browser]", data)
        }
        onStarted: {
            for (const line of root._unsent) proc.write(line);
            root._unsent = [];
        }
        onExited: (exitCode, exitStatus) => {
            const error = root._stopReason.length > 0 ? root._stopReason : "browser exited";
            root._stopReason = "";
            root.pid = 0;
            root.refs = ({});
            root.title = "";
            root.url = "";
            root.paused = false;
            for (const id of Object.keys(root._waiting)) root.answer(id, { "ok": false, "error": error });
            root.inFlight = 0;
        }
    }

    // A new chat, or another thread, is a new session; the browser does not carry over.
    property string _threadId: ""
    readonly property Connections chatWatch: Connections {
        target: root.engine?.conversation ?? null
        function onMessageIDsChanged() {
            if (root.engine.conversation.messageIDs.length === 0) root.stop("the chat was cleared");
        }
        function onThreadIdChanged() {
            const next = root.engine.conversation.threadId;
            if (root._threadId.length > 0 && next !== root._threadId) root.stop("another chat was opened");
            root._threadId = next;
        }
    }
}

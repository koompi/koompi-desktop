pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Desktop control for one AI session: one scripts/ai/desktop.py, started by the first
 * request and closed by a new chat, the stop key, the screen locking, a minute and a
 * half with no step, or the shell exiting. One JSON request per line in, one reply per
 * line out, routed back to its caller by id. `engine` is the Ai facade.
 *
 * The driver takes its Hyprland instance and session bus from the environment it is
 * started in, which is the shell's, and refuses every op when it cannot tell which.
 */
QtObject {
    id: root

    property QtObject engine

    readonly property bool running: proc.running
    property int inFlight: 0
    // ref number -> what the last windows or tree reply said it is (`button "Delete" (default)`).
    // The driver sends these as data beside the text, so a window cannot forge one.
    property var refs: ({})
    // the window the last step worked in, as the driver named it
    property string window: ""
    property string address: ""
    property double lastReplyAt: 0
    // The user took over: every step waits for them until they resume.
    property bool paused: false
    readonly property int idleMs: 90000
    // Screenshots (`see`): where the driver writes them, the newest one, and the remote
    // providers the user let see the screen in this chat, by host (screen-rules.js gate).
    // The images and the consents end with the chat, not with the driver.
    readonly property string shotsDir: (root.engine?.requester?.scriptDirPath ?? "").length > 0 ? `${root.engine.requester.scriptDirPath}/screens` : ""
    property string lastImage: ""
    property var consents: ({})

    property int _nextId: 0
    property var _waiting: ({})
    property var _unsent: []
    property string _stopReason: ""

    readonly property string driverPath: `${Directories.scriptPath}/ai/desktop.py`.replace(/file:\/\//, "")

    function request(op: string, fields: var, callback) {
        const id = ++root._nextId;
        root._waiting[id] = { "op": op, "callback": callback };
        root.inFlight++;
        idle.stop();
        const line = JSON.stringify(Object.assign({}, fields, { "id": id, "op": op })) + "\n";
        if (proc.running) {
            proc.write(line);
            return;
        }
        root._unsent = [...root._unsent, line];
        root._stopReason = "";
        proc.running = true;
    }

    // SIGTERM ends the driver; whoever is waiting is answered once it has gone, with `reason`.
    function stop(reason: string) {
        root._unsent = [];
        if (!proc.running) {
            for (const id of Object.keys(root._waiting)) root.answer(id, { "ok": false, "error": reason });
            return;
        }
        root._stopReason = reason;
        proc.running = false;
    }

    // Mirrors the driver's refs: every windows or tree reply replaces them, a failed step keeps them.
    function remember(reply) {
        if (reply.refs) root.refs = reply.refs;
        if (reply.window !== undefined) root.window = reply.window;
        if (reply.address !== undefined) root.address = reply.address;
        if (reply.image) root.lastImage = reply.image;
    }

    // A new chat forgets what was consented and deletes what was seen.
    function forgetScreens() {
        root.consents = ({});
        root.lastImage = "";
        // the last request body may hold a screenshot's base64 too
        const dir = root.engine?.requester?.scriptDirPath ?? "";
        if (dir.startsWith("/") && dir.length > 1)
            Quickshell.execDetached(["rm", "-rf", "--", `${dir}/screens`, `${dir}/request-body.json`]);
    }

    function answer(id, reply) {
        const waiting = root._waiting[id];
        if (!waiting) return;
        delete root._waiting[id];
        root.inFlight = Math.max(0, root.inFlight - 1);
        root.lastReplyAt = Date.now();
        root.remember(reply);
        if (root.inFlight === 0 && proc.running) idle.restart();
        waiting.callback(reply);
    }

    readonly property Timer idle: Timer {
        interval: root.idleMs
        onTriggered: if (root.inFlight === 0) root.stop("desktop control ended after a pause with no step")
    }

    readonly property Process proc: Process {
        stdinEnabled: true
        command: ["python3", "-I", root.driverPath, "--shots", root.shotsDir]
        stdout: SplitParser {
            onRead: line => {
                let reply;
                try {
                    reply = JSON.parse(line);
                } catch (e) {
                    console.warn(`[Ai:desktop] not a reply: ${line.slice(0, 200)}`);
                    return;
                }
                root.answer(reply.id, reply);
            }
        }
        stderr: SplitParser {
            onRead: data => console.warn("[Ai:desktop]", data)
        }
        onStarted: {
            for (const line of root._unsent) proc.write(line);
            root._unsent = [];
        }
        onExited: (exitCode, exitStatus) => {
            const error = root._stopReason.length > 0 ? root._stopReason : "desktop control exited";
            root._stopReason = "";
            idle.stop();
            root.refs = ({});
            root.window = "";
            root.address = "";
            root.paused = false;
            for (const id of Object.keys(root._waiting)) root.answer(id, { "ok": false, "error": error });
            root.inFlight = 0;
        }
    }

    // The driver refuses on a locked screen by itself; this also lets go of it at once.
    readonly property Connections lockWatch: Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked) root.stop("The screen locked; desktop control has ended.");
        }
    }

    // what an earlier shell left in the runtime dir belongs to no chat now
    Component.onCompleted: root.forgetScreens()

    // A new chat, or another thread, is a new session; desktop control does not carry over.
    property string _threadId: ""
    readonly property Connections chatWatch: Connections {
        target: root.engine?.conversation ?? null
        function onMessageIDsChanged() {
            if (root.engine.conversation.messageIDs.length > 0) return;
            root.stop("the chat was cleared");
            root.forgetScreens();
        }
        function onThreadIdChanged() {
            const next = root.engine.conversation.threadId;
            if (root._threadId.length > 0 && next !== root._threadId) {
                root.stop("another chat was opened");
                root.forgetScreens();
            }
            root._threadId = next;
        }
    }
}

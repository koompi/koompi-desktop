//@ pragma Env QS_NO_RELOAD_POPUP=1

// The AI engine with no surfaces. scripts/ai/headless.sh is the way in: it names the
// job in KOOMPI_AI_HEADLESS_JOB and the result in KOOMPI_AI_HEADLESS_OUT.

import "modules/common"
import "services"

import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    property var job: null
    property int turn: -1
    property var requests: []
    property int requestsAtTurnStart: 0
    property int idleTicks: 0
    property double startedAt: Date.now()
    property bool finished: false
    property bool stopped: false

    readonly property FileView jobFile: FileView {
        path: Quickshell.env("KOOMPI_AI_HEADLESS_JOB") ?? ""
        blockAllReads: true
    }
    readonly property FileView outFile: FileView {
        path: Quickshell.env("KOOMPI_AI_HEADLESS_OUT") ?? ""
        blockWrites: true
    }
    readonly property FileView requestFile: FileView {
        blockAllReads: true
        watchChanges: false
    }

    function modelId(): string {
        const m = root.job?.model;
        return `${typeof m === "string" ? m : (m?.model ?? "")}`.trim().toLowerCase();
    }

    // The body Requester wrote for curl, read back out of `--data '...'`.
    function captureRequest() {
        root.requestFile.path = Ai.requester.scriptFilePath;
        root.requestFile.reload();
        const text = root.requestFile.text();
        const marker = " --data '";
        const start = text.indexOf(marker);
        const end = text.lastIndexOf("'");
        let body = null;
        if (start >= 0 && end > start) {
            try {
                body = JSON.parse(text.slice(start + marker.length, end).split("'\\''").join("'"));
            } catch (e) {
                body = { "unparsed": `${e}` };
            }
        }
        root.requests = [...root.requests, { "at": Date.now(), "body": body }];
    }

    function messageData(id) {
        const m = Ai.messageByID[id];
        return {
            "role": m.role,
            "content": m.content,
            "rawContent": m.rawContent,
            "model": m.model,
            "timestamp": m.timestamp,
            "done": m.done,
            "visibleToUser": m.visibleToUser,
            "functionName": m.functionName,
            "functionCall": m.functionCall ?? null,
            "toolCalls": m.toolCalls ?? [],
            "toolCallId": m.toolCallId,
            "functionResponse": m.functionResponse,
            "sources": m.sources ?? []
        };
    }

    function finish(ok: bool, error: string) {
        if (root.finished) return;
        root.finished = true;
        Ai.cancelRequest();
        Ai.browserTool.service.stop("the headless run finished");
        root.outFile.setText(JSON.stringify({
            "ok": ok,
            "error": error,
            "model": root.modelId(),
            "promptDir": Config.promptSectionDir,
            "systemPrompt": Ai.systemPrompt,
            "tokenCount": { "input": Ai.tokenCount.input, "output": Ai.tokenCount.output, "total": Ai.tokenCount.total },
            "wallMs": Date.now() - root.startedAt,
            "messages": Ai.messageIDs.map(id => root.messageData(id)),
            "requests": root.requests
        }, null, 2) + "\n");
        Qt.quit();
    }

    // A tool that waits for the user gets the job's answer instead; unlisted means no.
    function answerApprovals() {
        for (const id of Ai.messageIDs) {
            const m = Ai.messageByID[id];
            if (!m.functionPending) continue;
            const name = m.functionCall?.name ?? m.functionName;
            if ((root.job.approvals ?? {})[name] === "approve") Ai.approveCommand(m, false);
            else Ai.rejectCommand(m);
        }
    }

    function busy(): bool {
        if (Ai.requester.running || Ai.compacting) return true;
        if (Ai.toolRunner._queue.length > 0 || Ai.toolRunner._currentCallId.length > 0) return true;
        return Ai.toolRunner.toolStatusLabel.length > 0;
    }

    // A stubbed tool answers with the job's text and never runs: no web, no shell, no agent.
    function installStubs() {
        const stubs = root.job.stubs ?? {};
        for (const name in stubs) {
            const output = `${stubs[name]}`;
            Ai.toolRunner.handlers[name] = (args, message) => {
                Ai.toolRunner.addToolResult(name, output, false);
                Ai.toolRunner.runNextCall();
            };
        }
    }

    function begin() {
        root.installStubs();
        Ai.clearMessages(false);
        Ai.setModel(root.modelId(), false, true);
        root.nextTurn();
    }

    function nextTurn() {
        root.turn++;
        const turns = root.job.turns ?? [];
        if (root.turn >= turns.length) {
            root.finish(true, "");
            return;
        }
        root.requestsAtTurnStart = root.requests.length;
        root.idleTicks = 0;
        Ai.sendUserMessage(`${turns[root.turn]}`);
    }

    function tick() {
        const limit = (root.job?.timeoutSec ?? 300) * 1000;
        if (Date.now() - root.startedAt > limit) {
            root.finish(false, `timeout after ${limit / 1000}s in turn ${root.turn}`);
            return;
        }
        if (root.turn < 0) {
            const toolTextReady = !root.job.toolTextFile || Ai.toolRegistry.toolText !== null;
            const ready = Config.ready && Persistent.ready && Config.composedSystemPrompt.length > 0 && toolTextReady;
            if (ready && root.modelId() in Ai.models) root.begin();
            return;
        }
        root.answerApprovals();
        if (root.job.stopFile && !root.stopped && !stopProbe.running) stopProbe.running = true;
        if (root.busy() || root.requests.length === root.requestsAtTurnStart) {
            root.idleTicks = 0;
            return;
        }
        if (++root.idleTicks >= 4) root.nextTurn();
    }

    Connections {
        target: Ai.requester
        function onRunningChanged() {
            if (Ai.requester.running) root.captureRequest();
        }
    }

    // the job's stop key: pressed once, when its file appears
    Process {
        id: stopProbe
        command: ["test", "-e", `${root.job?.stopFile ?? ""}`]
        onExited: exitCode => {
            if (exitCode !== 0 || root.stopped) return;
            root.stopped = true;
            Ai.stopControl();
        }
    }

    Timer {
        interval: 250
        repeat: true
        running: !root.finished
        onTriggered: root.tick()
    }

    Component.onCompleted: {
        try {
            root.job = JSON.parse(root.jobFile.text());
        } catch (e) {
            root.finish(false, `unreadable job ${root.jobFile.path}: ${e}`);
            return;
        }
        if (typeof root.job.model === "string") Ai.refreshLitertLmModels();
    }
}

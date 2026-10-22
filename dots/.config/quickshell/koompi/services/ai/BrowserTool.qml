pragma ComponentBehavior: Bound

import qs.modules.common
import qs.services
import QtQuick
import "browser-rules.js" as Rules

/**
 * The `browser` tool: the model's hands in the agent's own Chrome (BrowserService),
 * and the Control session's safety shell around them. Most steps run at once;
 * Rules.askReason names the consequential ones, which wait for the user through the
 * same card as a shell command, and while the user has taken the browser over
 * (`pause`) every step waits. The refusals (password fields, browser-internal
 * schemes) stay in browser.py, where no caller can talk its way past them.
 * `engine` is the Ai facade.
 */
QtObject {
    id: root

    property QtObject engine

    readonly property BrowserService service: BrowserService { engine: root.engine }

    // The browser is a way onto the web, so it follows the same switch as search_web
    // and fetch_url (`ai.webSearch`).
    readonly property var entry: Object.assign({}, Rules.entry, { "enabled": Config.options?.ai?.webSearch ?? true })

    function runsWithoutAsking(args: var): bool {
        return !root.service.paused && Rules.askReason(args, root.service.refs) === "";
    }

    // `approved` is true when the user has just answered this call's card.
    function handle(args: var, message: var, approved: bool) {
        const runner = root.engine.toolRunner;
        const req = Rules.requestOf(args);
        if (Rules.ops.indexOf(req.op) < 0) {
            runner.addToolResult("browser", `Unknown op "${req.op}". Use one of: ${Rules.ops.join(", ")}.`, false);
            runner.runNextCall();
            return;
        }
        if (!approved && !root.engine.approval.isPreApproved("browser", req)) {
            runner.askFirst(message, Translation.tr("Browser step request"), "browser",
                Rules.describe(req, root.service.refs), "browser", req);
            return;
        }
        // answering the card is the user handing the browser back
        root.service.paused = false;
        // a call-only turn has no prose, so its bubble would render empty
        if (message && (message.content ?? "").trim().length === 0) message.visibleToUser = false;
        root.run(req);
    }

    function run(req: var) {
        const runner = root.engine.toolRunner;
        const result = runner.addToolResult("browser", "", false);
        runner.toolStatusLabel = Translation.tr("Using the browser…");
        const fields = Object.assign({}, req);
        delete fields.op;
        root.service.request(req.op, fields, reply => {
            runner.toolStatusLabel = "";
            result.functionResponse = reply.ok
                ? `${reply.text ?? ""}`
                : `The browser step failed: ${reply.error ?? "no reply"}`;
            result.rawContent = result.functionResponse;
            if (reply.ok && /^https?:/.test(reply.url ?? ""))
                runner.addSource({ "type": "web", "name": reply.title || reply.url, "detail": "", "score": 0, "url": reply.url });
            runner.runNextCall();
        });
    }

    // The take-over pause, from the indicator or from the user focusing the agent's
    // window. Nothing in flight is interrupted; the next step waits for an answer.
    function pause() {
        if (root.service.running) root.service.paused = true;
    }

    // Resume answers a step that waited only because of the pause. A step that would
    // ask anyway keeps its card, so the user still sees what it is before it runs.
    function resume() {
        root.service.paused = false;
        const conversation = root.engine.conversation;
        for (const id of conversation.messageIDs) {
            const m = conversation.messageByID[id];
            if (!m?.functionPending || m.functionCall?.name !== "browser") continue;
            if (Rules.askReason(m.functionCall.args, root.service.refs) === "") root.engine.toolRunner.approveCommand(m, false);
        }
    }

    // The stop key: the turn ends and the browser closes, whatever it was doing.
    function stop() {
        root.engine.toolRunner.stopTurn();
        root.engine.requester.cancelRequest();
        root.service.stop("Stopped by the user; the browser is closed.");
    }
}

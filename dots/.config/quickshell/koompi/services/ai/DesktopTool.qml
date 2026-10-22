pragma ComponentBehavior: Bound

import qs.modules.common
import qs.services
import QtQuick
import "desktop-rules.js" as Rules

/**
 * The `desktop` tool: the model's hands in the user's own apps (DesktopService runs
 * scripts/ai/desktop.py), and the Control session's safety shell around them, as
 * BrowserTool is for the agent's browser. Most steps run at once; Rules.askReason
 * names the consequential ones, which wait for the user through the same card as a
 * shell command, and while the user has taken over (`pause`) every step waits. The
 * refusals (the lock screen, the shell's own surfaces, authentication, terminals,
 * browsers, password fields) stay in desktop.py, where no caller can talk past them.
 * `engine` is the Ai facade.
 */
QtObject {
    id: root

    property QtObject engine

    readonly property DesktopService service: DesktopService { engine: root.engine }
    readonly property var entry: Rules.entry

    function runsWithoutAsking(args: var): bool {
        return !root.service.paused && Rules.askReason(args, root.service.refs) === "";
    }

    // `approved` is true when the user has just answered this call's card.
    function handle(args: var, message: var, approved: bool) {
        const runner = root.engine.toolRunner;
        const req = Rules.requestOf(args);
        if (Rules.ops.indexOf(req.op) < 0) {
            runner.addToolResult("desktop", `Unknown op "${req.op}". Use one of: ${Rules.ops.join(", ")}.`, false);
            runner.runNextCall();
            return;
        }
        if (!approved && !root.engine.approval.isPreApproved("desktop", req)) {
            runner.askFirst(message, Translation.tr("Desktop step request"), "desktop",
                Rules.describe(req, root.service.refs, root.service.window), "desktop", req);
            return;
        }
        // answering the card is the user handing control back
        root.service.paused = false;
        // a call-only turn has no prose, so its bubble would render empty
        if (message && (message.content ?? "").trim().length === 0) message.visibleToUser = false;
        root.run(req);
    }

    function run(req: var) {
        const runner = root.engine.toolRunner;
        const result = runner.addToolResult("desktop", "", false);
        runner.toolStatusLabel = Translation.tr("Using your apps…");
        const fields = Object.assign({}, req);
        delete fields.op;
        root.service.request(req.op, fields, reply => {
            runner.toolStatusLabel = "";
            result.functionResponse = reply.ok
                ? `${reply.text ?? ""}`
                : `The desktop step failed: ${reply.error ?? "no reply"}`;
            result.rawContent = result.functionResponse;
            runner.runNextCall();
        });
    }

    // The take-over pause, from the indicator or from the user switching windows.
    // Nothing in flight is interrupted; the next step waits for an answer.
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
            if (!m?.functionPending || m.functionCall?.name !== "desktop") continue;
            if (Rules.askReason(m.functionCall.args, root.service.refs) === "") root.engine.toolRunner.approveCommand(m, false);
        }
    }

    // The stop key ends desktop control with the turn; the caller ends the turn.
    function stop() {
        root.service.stop("Stopped by the user; desktop control has ended.");
    }
}

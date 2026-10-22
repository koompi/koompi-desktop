pragma ComponentBehavior: Bound

import qs.modules.common
import qs.services
import QtQuick
import "desktop-rules.js" as Rules
import "screen-rules.js" as Screen

/**
 * The `desktop` tool: the model's hands in the user's own apps (DesktopService runs
 * scripts/ai/desktop.py), and the Control session's safety shell around them, as
 * BrowserTool is for the agent's browser. Most steps run at once; Rules.askReason
 * names the consequential ones, which wait for the user through the same card as a
 * shell command, and while the user has taken over (`pause`) every step waits. The
 * refusals (the lock screen, the shell's own surfaces, authentication, terminals,
 * browsers, password fields) stay in desktop.py, where no caller can talk past them.
 * A screenshot (`see`) goes to a remote model only after the user allowed that provider
 * for this chat, on a card of its own, and never under policies.ai == 2 (plan D8).
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
        // a screenshot first passes the screen gate, which may ask for consent; that card
        // stands for the take-over card too. Only a card the user answered carries `consent`.
        if (req.op === "see") {
            if (approved && typeof args.consent === "string" && args.consent.length > 0)
                root.service.consents = Object.assign({}, root.service.consents, { [args.consent]: true });
            const gate = root.screenGate();
            if (!gate.send) {
                if (gate.ask && message) {
                    runner.askFirst(message, Translation.tr("Screen sharing request"), "desktop",
                        Rules.describe(req, root.service.refs, root.service.window), "desktop",
                        Object.assign({}, req, { "consent": gate.provider.key }));
                    message.functionCall = Object.assign({}, message.functionCall, { "consent": gate.provider.label });
                    return;
                }
                runner.addToolResult("desktop", `No screenshot was taken: ${gate.reason}. Use tree to read the window.`, false);
                runner.runNextCall();
                return;
            }
        }
        if (!approved && !root.engine.approval.isPreApproved("desktop", req)) {
            runner.askFirst(message, Translation.tr("Desktop step request"), "desktop",
                Rules.describe(req, root.service.refs, root.service.window), "desktop", req);
            // a click by pixels is judged by what is under the mark: the card shows the screenshot
            if (Rules.isRegion(req, root.service.refs) && root.service.lastImage.length > 0)
                message.functionCall = Object.assign({}, message.functionCall, { "image": root.service.lastImage });
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
            if (reply.ok && reply.image) result.imageFile = reply.image;
            runner.runNextCall();
        });
    }

    // May a screenshot go to the model in use now? (screen-rules.js gate)
    function screenGate(): var {
        return Screen.gate(root.engine.models[root.engine.currentModelId], Config.options?.policies?.ai, root.service.consents);
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
            // a consent is the user's own answer; Resume never gives it
            if (!m?.functionPending || m.functionCall?.name !== "desktop" || m.functionCall?.consent) continue;
            if (Rules.askReason(m.functionCall.args, root.service.refs) === "") root.engine.toolRunner.approveCommand(m, false);
        }
    }

    // The stop key ends desktop control with the turn; the caller ends the turn.
    function stop() {
        root.service.stop("Stopped by the user; desktop control has ended.");
    }
}

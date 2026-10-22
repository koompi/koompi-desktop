pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * The ChatGPT plan sign-in as the shell sees it, through scripts/ai/chatgpt_auth.py:
 * `status` for who is signed in, `login` (opens the browser and waits on the
 * loopback), `logout`. A singleton so a sign-in survives leaving Settings > AI and
 * the sidebar can offer one too. No token ever reaches QML: `status` prints none.
 * KOOMPI_CHATGPT_AUTH names another helper, for tests.
 */
Singleton {
    id: root

    property bool known: false // a status has been read
    property bool signedIn: false
    property string email: ""
    property bool planUsage: false
    readonly property bool signingIn: login.running
    readonly property bool signingOut: logout.running
    // the page the browser was sent to, for "Open the page again"
    property string signInUrl: ""
    // what went wrong with the last sign-in or sign-out, in plain words; "" when nothing
    property string problem: ""

    // TODO(M3): OpenAI's "Manage usage" destination is not in chatgpt_auth.py or the
    // plan's notes; take it from developers.openai.com/siwc/ui-ux-guidelines. While
    // empty, Settings > AI does not show the link.
    readonly property string manageUsageUrl: ""

    readonly property string helper: {
        const override = Quickshell.env("KOOMPI_CHATGPT_AUTH") ?? "";
        return override.length > 0 ? override : FileUtils.trimFileProtocol(`${Directories.scriptPath}/ai/chatgpt_auth.py`);
    }

    function refresh() {
        if (!status.running) status.running = true;
    }

    function signIn() {
        if (login.running) return;
        root.problem = "";
        root.signInUrl = "";
        root._cancelled = false;
        login.running = true;
    }

    property bool _cancelled: false
    function cancelSignIn() {
        if (!login.running) return;
        root._cancelled = true;
        login.running = false;
    }

    function signOut() {
        if (logout.running) return;
        root.problem = "";
        logout.running = true;
    }

    function reopenSignInPage() {
        if (root.signInUrl.length > 0) Qt.openUrlExternally(root.signInUrl);
    }

    // chatgpt_auth.py's exits: 1 failed, 3 no plan scope, 4 sign in again, 5 network
    function problemFor(exitCode: int): string {
        if (exitCode === 5) return Translation.tr("Couldn't reach OpenAI. Check your connection and try again.");
        if (exitCode === 3) return Translation.tr("This account's sign-in doesn't include plan usage.");
        return Translation.tr("Sign-in didn't finish. Try again.");
    }

    readonly property Process status: Process {
        command: [root.helper, "status"]
        stdout: StdioCollector {
            id: statusOut
            onStreamFinished: {
                try {
                    const state = JSON.parse(statusOut.text);
                    root.signedIn = state.signed_in === true;
                    root.email = root.signedIn ? `${state.email ?? ""}` : "";
                    root.planUsage = root.signedIn && state.plan_usage === true;
                    root.known = true;
                } catch (e) {
                    console.warn("[ChatGptAccount] status gave no JSON");
                }
            }
        }
    }

    readonly property Process login: Process {
        command: [root.helper, "login"]
        stdout: SplitParser {
            onRead: line => {
                const url = line.trim();
                if (/^https?:\/\//.test(url)) root.signInUrl = url;
            }
        }
        // stderr carries the helper's own wording; it goes to the journal, not the page
        stderr: SplitParser {
            onRead: line => console.log(`[ChatGptAccount] ${line}`)
        }
        onExited: (exitCode, exitStatus) => {
            root.signInUrl = "";
            // a cancel is a choice, not a failure; exitStatus 0 is a normal exit, not a signal
            if (exitCode !== 0 && exitStatus === 0 && !root._cancelled) root.problem = root.problemFor(exitCode);
            root.refresh();
        }
    }

    readonly property Process logout: Process {
        command: [root.helper, "logout"]
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) root.problem = Translation.tr("Sign-out didn't finish. Try again.");
            root.refresh();
        }
    }

    Component.onCompleted: root.refresh()
}

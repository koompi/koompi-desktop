#!/usr/bin/env bash
# Settings > AI > Providers, driven in a headless KWin on a private bus with `qs -p`:
# ProvidersSection loaded as the page loads it, with a stand-in chatgpt_auth.py
# (KOOMPI_CHATGPT_AUTH), a stand-in secret-tool backed by a file in the work dir and
# a throwaway config.json. The probe signs in (a failure first, then a success), adds
# a plan model, signs out, saves, replaces and removes API keys, and adds a custom
# endpoint, then the shell side reads what reached the keyring file and config.json.
# Nothing here reaches OpenAI, a real keyring or the user's config.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"
SETTINGS="$SHELL_ROOT/modules/settings/ai"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

for f in ProvidersSection.qml ChatGptProvider.qml ApiKeyProviders.qml ApiKeyRow.qml CustomEndpoints.qml EndpointForm.qml ProviderRow.qml qmldir; do
    [[ -f "$SETTINGS/$f" ]] || fail "missing $SETTINGS/$f"
done
grep -q 'ProvidersSection {}' "$SHELL_ROOT/modules/settings/AiConfig.qml" || fail "AiConfig.qml does not show ProvidersSection"
grep -q 'readonly property string helper' "$SHELL_ROOT/services/ChatGptAccount.qml" || fail "ChatGptAccount has no helper path"
# no key is ever logged, held for display, or put in a file from QML
grep -nE 'console\.(log|warn|error)\([^)]*(keyField|value|key\b)' "$SETTINGS"/ApiKeyRow.qml "$SHELL_ROOT/services/ai/KeyGate.qml" \
    && fail "a key reaches a log line"
echo "ok   static: the page shows Providers; keys are not logged"

QMLLINT=/usr/lib/qt6/bin/qmllint
if [[ -x "$QMLLINT" ]]; then
    LINT="$(mktemp -d)"
    ln -s "$SHELL_ROOT" "$LINT/qs"
    for f in "$SETTINGS"/*.qml "$SHELL_ROOT/services/ChatGptAccount.qml" "$SHELL_ROOT/services/AiProviders.qml" "$SHELL_ROOT/modules/settings/AiConfig.qml"; do
        out="$("$QMLLINT" -I "$LINT" -I /usr/lib/qt6/qml "$f" 2>&1)"
        grep -qE '^Error' <<< "$out" && { echo "$out" | grep -A3 '^Error' >&2; rm -rf "$LINT"; fail "qmllint error in $(basename -- "$f")"; }
    done
    rm -rf "$LINT"
    echo "ok   qmllint: no errors in the Providers files"
else
    echo "skip: no Qt 6 qmllint at $QMLLINT"
fi

if ! command -v qs > /dev/null 2>&1; then
    echo "skip: quickshell (qs) not installed, static checks only"
    exit 0
fi
for tool in kwin_wayland dbus-run-session; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed, static checks only"; exit 0; }
done

WORK="$(mktemp -d)"
trap '[[ -n ${KEEP_WORK:-} ]] && echo "work: $WORK" || rm -rf "$WORK"' EXIT
mkdir -p "$WORK/shell" "$WORK/bin" "$WORK/auth" "$WORK/xdg/config/koompi" "$WORK/xdg/state" "$WORK/xdg/cache" "$WORK/home" "$WORK/rt"
chmod 700 "$WORK/rt"
for entry in "$SHELL_ROOT"/*; do
    ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"
done

# the keyring: one JSON item in a file; a gemini key is already there
printf '{"apiKeys": {"gemini": "gm-existing-key"}}' > "$WORK/keyring.json"
cat > "$WORK/bin/secret-tool" << SH
#!/usr/bin/env bash
case "\$1" in
    lookup) cat "$WORK/keyring.json" 2> /dev/null ;;
    store) cat > "$WORK/keyring.json" ;;
    *) exit 1 ;;
esac
SH
printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/ollama"

# chatgpt_auth.py's CLI: status JSON, login prints the page then waits, logout
cat > "$WORK/auth/chatgpt_auth" << SH
#!/usr/bin/env bash
echo "\$1" >> "$WORK/auth/calls"
case "\$1" in
    status)
        if [[ -f "$WORK/auth/signed_in" ]]; then
            printf '{"signed_in": true, "email": "probe@example.com", "plan_usage": true, "expires_at": 0}\n'
        else
            printf '{"signed_in": false, "email": null, "plan_usage": false, "expires_at": null}\n'
        fi ;;
    login)
        printf 'Sign in to ChatGPT in your browser. If it did not open, visit:\nhttp://127.0.0.1:9/oauth/authorize?probe=1\n'
        sleep 1
        if [[ -f "$WORK/auth/fail_next" ]]; then
            rm -f "$WORK/auth/fail_next"
            echo "Couldn't reach OpenAI." >&2
            exit 5
        fi
        touch "$WORK/auth/signed_in" ;;
    logout) rm -f "$WORK/auth/signed_in" ;;
esac
SH
touch "$WORK/auth/fail_next"
chmod +x "$WORK/bin"/* "$WORK/auth/chatgpt_auth"
printf '{"configVersion": 1, "ai": {"extraModels": []}}\n' > "$WORK/xdg/config/koompi/config.json"

cat > "$WORK/shell/providers_probe.qml" << 'QML'
import qs.modules.settings.ai
import qs.modules.koompi.sidebarLeft.aiChat.composer
import qs.modules.common
import qs.services
import Quickshell
import QtQuick
import QtQuick.Layouts

ShellRoot {
    id: probe
    property int failures: 0
    property int step: 0
    property int ticks: 0

    function check(label, got, want) {
        const ok = JSON.stringify(got) === JSON.stringify(want);
        console.log((ok ? "PASS " : "FAIL ") + label + "  got=" + JSON.stringify(got) + (ok ? "" : " want=" + JSON.stringify(want)));
        if (!ok) probe.failures++;
    }
    function find(item, pred) {
        if (!item) return null;
        if (pred(item)) return item;
        const kids = item.children ?? [];
        for (let i = 0; i < kids.length; i++) {
            const hit = probe.find(kids[i], pred);
            if (hit) return hit;
        }
        return null;
    }
    function named(name, within) { return probe.find(within ?? page, item => item.objectName === name); }
    function keyRow(keyId) { return probe.find(page, item => item.keyId === keyId && item.saved !== undefined); }
    function shown(item) {
        for (let it = item; it; it = it.parent) if (!it.visible) return false;
        return item !== null;
    }
    function models() { return JSON.parse(JSON.stringify(Config.options.ai.extraModels)); }

    Item {
        width: 900
        height: 2400
        ColumnLayout {
            id: page
            width: 900
            ProvidersSection {}
        }
        ModelPicker {
            id: picker
            width: 320
            visible: false
            models: [
                { id: "gpt-5", name: "GPT-5", description: "OpenAI", auth: "chatgpt" },
                { id: "gemini-2.5-flash", name: "Gemini", description: "Google", auth: "" }
            ]
            currentId: "gpt-5"
        }
    }

    // each step waits for its condition, then acts; 30 s in all
    readonly property var steps: [
        { why: "config, keyring and sign-in status read", until: () => Config.ready && KeyringStorage.loaded && ChatGptAccount.known, act: () => {
            probe.check("signed out: Continue with ChatGPT is shown", probe.shown(probe.named("continueWithChatGpt")), true);
            probe.check("signed out: no Sign out", probe.shown(probe.named("signOut")), false);
            probe.check("the saved gemini key reads as saved", probe.keyRow("gemini").saved, true);
            probe.check("openai has no key", probe.keyRow("openai").saved, false);
            probe.check("no endpoints yet: Add endpoint is shown", probe.shown(probe.named("addEndpoint")), true);
            probe.named("continueWithChatGpt").clicked();
        } },
        { why: "the sign-in page URL", until: () => ChatGptAccount.signInUrl.length > 0, act: () => {
            probe.check("signing in: the page's URL is kept for Open the page again", ChatGptAccount.signInUrl, "http://127.0.0.1:9/oauth/authorize?probe=1");
            probe.check("signing in: Cancel is shown", probe.shown(probe.named("cancelSignIn")), true);
            probe.check("signing in: Continue is hidden", probe.shown(probe.named("continueWithChatGpt")), false);
        } },
        { why: "the failed sign-in to finish", until: () => !ChatGptAccount.signingIn && ChatGptAccount.problem.length > 0, act: () => {
            probe.check("exit 5 says so in plain words", ChatGptAccount.problem, "Couldn't reach OpenAI. Check your connection and try again.");
            probe.check("still signed out", ChatGptAccount.signedIn, false);
            ChatGptAccount.signIn();
            probe.check("a new attempt clears the problem", ChatGptAccount.problem, "");
        } },
        { why: "the second sign-in", until: () => !ChatGptAccount.signingIn && ChatGptAccount.signedIn, act: () => {
            probe.check("signed in as the account status names", ChatGptAccount.email, "probe@example.com");
            probe.check("signed in: Sign out is shown", probe.shown(probe.named("signOut")), true);
            probe.check("signed in: Continue is hidden", probe.shown(probe.named("continueWithChatGpt")), false);
            const field = probe.named("planModelField");
            probe.check("signed in: a plan model can be added", probe.shown(field), true);
            field.text = "GPT-5";
            field.accepted();
            field.text = "gpt-5";
            field.accepted();
        } },
        { why: "the plan model in config", until: () => probe.models().length === 1, act: () => {
            const entry = probe.models()[0];
            probe.check("the plan model is a Responses entry with the sign-in", [entry.model, entry.auth, entry.api_format, entry.endpoint, entry.requires_key],
                ["GPT-5", "chatgpt", "responses", "https://api.openai.com/v1/responses", false]);
            probe.check("a second add of the same id is refused", probe.find(page, item => item.addProblem !== undefined).addProblem, "That model is already in the list.");
            probe.named("signOut").clicked();
        } },
        { why: "signed out again", until: () => ChatGptAccount.known && !ChatGptAccount.signedIn && !ChatGptAccount.signingOut, act: () => {
            probe.check("signed out: Continue is back", probe.shown(probe.named("continueWithChatGpt")), true);
            probe.check("the plan model stays in the list", probe.models().length, 1);

            const openai = probe.keyRow("openai");
            probe.named("setKey", openai).clicked();
            probe.check("Add key opens the field", probe.shown(probe.named("keyField", openai)), true);
            probe.check("Save waits for a key", probe.named("saveKey", openai).enabled, false);
            probe.named("keyField", openai).text = "  sk-probe-openai-1  ";
            probe.named("saveKey", openai).clicked();
            probe.check("the key is stored trimmed", KeyringStorage.keyringData.apiKeys.openai, "sk-probe-openai-1");
            probe.check("the other key is kept", KeyringStorage.keyringData.apiKeys.gemini, "gm-existing-key");
            probe.check("the row reads Key saved, the field is closed and empty", [openai.saved, openai.mode, probe.named("keyField", openai).text], [true, "", ""]);

            probe.named("setKey", openai).clicked();
            probe.named("keyField", openai).text = "sk-probe-openai-2";
            probe.named("saveKey", openai).clicked();
            probe.check("Replace overwrites it", KeyringStorage.keyringData.apiKeys.openai, "sk-probe-openai-2");

            const gemini = probe.keyRow("gemini");
            probe.named("removeKey", gemini).clicked();
            probe.check("Remove asks first", [gemini.mode, KeyringStorage.keyringData.apiKeys.gemini], ["removing", "gm-existing-key"]);
            probe.named("confirmRemove", gemini).clicked();
            probe.check("confirmed, the key is gone and the other stays",
                [KeyringStorage.keyringData.apiKeys.gemini === undefined, KeyringStorage.keyringData.apiKeys.openai], [true, "sk-probe-openai-2"]);

            probe.named("addEndpoint").clicked();
        } },
        { why: "the endpoint form", until: () => probe.named("newEndpointForm") !== null, act: () => {
            const form = probe.named("newEndpointForm");
            probe.named("endpointBase", form).text = "ftp://box";
            probe.named("endpointSave", form).clicked();
            probe.check("a bad form says what is wrong beside each field and keeps the typing",
                [(form.problems.model ?? "").length > 0, (form.problems.baseUrl ?? "").length > 0, probe.named("endpointBase", form).text], [true, true, "ftp://box"]);
            probe.check("nothing was written", probe.models().length, 1);
            probe.named("endpointName", form).text = "Home box";
            probe.named("endpointBase", form).text = "https://llm.example.invalid/v1";
            probe.named("endpointModel", form).text = "qwen3-32b";
            form.format = "responses";
            probe.named("endpointSave", form).clicked();
        } },
        { why: "the endpoint in config", until: () => probe.models().length === 2, act: () => {
            const entry = probe.models()[1];
            probe.check("the endpoint entry", [entry.model, entry.name, entry.endpoint, entry.api_format, entry.requires_key, entry.key_id],
                ["qwen3-32b", "Home box", "https://llm.example.invalid/v1/responses", "responses", true, "custom:llm.example.invalid"]);
            probe.check("the form closed", probe.named("newEndpointForm"), null);
            const keyRow = probe.keyRow("custom:llm.example.invalid");
            probe.check("the endpoint has its own key row", probe.shown(keyRow), true);
            probe.named("setKey", keyRow).clicked();
            probe.named("keyField", keyRow).text = "sk-probe-endpoint";
            probe.named("saveKey", keyRow).clicked();
            probe.check("its key is stored under its key id", KeyringStorage.keyringData.apiKeys["custom:llm.example.invalid"], "sk-probe-endpoint");

            picker.visible = true;
            probe.check("the picker says a plan model uses the plan, and nothing for the other", [picker.rowAt(0).usesPlan, picker.rowAt(1).usesPlan], [true, false]);
        } },
        { why: "config and keyring writes to land", until: () => probe.ticks > 8, act: () => {} },
    ]

    Timer {
        interval: 100; running: true; repeat: true
        property int waited: 0
        onTriggered: {
            const current = probe.steps[probe.step];
            if (!current) {
                console.log(probe.failures === 0 ? "PROBE OK" : "PROBE FAILED " + probe.failures);
                Qt.quit();
                return;
            }
            if (probe.step === probe.steps.length - 1) probe.ticks++;
            if (current.until()) {
                waited = 0;
                current.act();
                probe.step++;
            } else if (++waited > 300) {
                console.log("FAIL timed out waiting for " + current.why);
                probe.failures++;
                probe.step = probe.steps.length;
            }
        }
    }
}
QML

cat > "$WORK/inner.sh" << SH
#!/usr/bin/env bash
cd "$WORK/shell" || exit 1
timeout 60 qs -p providers_probe.qml > "$WORK/qs.log" 2>&1
SH
chmod +x "$WORK/inner.sh"

env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY -u DISPLAY QT_QPA_PLATFORM=wayland KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 \
    HOME="$WORK/home" XDG_RUNTIME_DIR="$WORK/rt" PATH="$WORK/bin:$PATH" KOOMPI_CHATGPT_AUTH="$WORK/auth/chatgpt_auth" \
    XDG_CONFIG_HOME="$WORK/xdg/config" XDG_STATE_HOME="$WORK/xdg/state" XDG_CACHE_HOME="$WORK/xdg/cache" \
    timeout 120 dbus-run-session --config-file="$REPO_ROOT/tests/private-bus.conf" -- kwin_wayland --virtual --width 1280 --height 800 \
        --no-lockscreen --no-global-shortcuts --exit-with-session "$WORK/inner.sh" > "$WORK/kwin.log" 2>&1
out="$(sed 's/\x1b\[[0-9;]*m//g' "$WORK/qs.log" 2> /dev/null)"
echo "$out" | sed -n 's/^ DEBUG qml: //p' | grep -E '^(PASS|FAIL|PROBE)' || true
if ! grep -q "PROBE OK" <<< "$out"; then
    echo "--- probe output ---" >&2
    echo "$out" | grep -vE "qmlscanner|^\s*$" | tail -40 >&2
    echo "--- kwin ---" >&2
    tail -20 "$WORK/kwin.log" >&2
    fail "the Providers probe did not pass"
fi

# what reached the outside: the keyring file, config.json, the helper's calls
keyring="$(cat "$WORK/keyring.json")"
python3 -I - "$WORK/keyring.json" << 'PY' || fail "the keyring item is not what the page wrote: $keyring"
import json, sys
keys = json.load(open(sys.argv[1]))["apiKeys"]
assert keys == {"openai": "sk-probe-openai-2", "custom:llm.example.invalid": "sk-probe-endpoint"}, keys
PY
python3 -I - "$WORK/xdg/config/koompi/config.json" << 'PY' || fail "config.json does not hold the two models"
import json, sys
models = json.load(open(sys.argv[1]))["ai"]["extraModels"]
assert [m["model"] for m in models] == ["GPT-5", "qwen3-32b"], models
PY
for secret in sk-probe-openai-1 sk-probe-openai-2 sk-probe-endpoint gm-existing-key; do
    grep -rqF -- "$secret" "$WORK/xdg" && fail "a key ($secret) is in a config or state file"
    # the probe's own PASS/FAIL lines print what they compared; anything else is the shell
    grep -vE '(PASS|FAIL) ' "$WORK/qs.log" | grep -qF -- "$secret" && fail "a key ($secret) is in the shell's log"
done
calls="$(sort "$WORK/auth/calls" | uniq -c | awk '{print $2"="$1}' | tr '\n' ' ')"
grep -q 'login=2' <<< "$calls" && grep -q 'logout=1' <<< "$calls" || fail "the helper was not called as expected: $calls"
echo "ok   providers: sign-in failure then success, plan model, sign-out, key add/replace/remove, custom endpoint with its key; keys only in the keyring item (helper calls: $calls)"

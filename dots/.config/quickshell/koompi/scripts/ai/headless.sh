#!/usr/bin/env bash
# headless.sh JOB.json OUT.json: run the AI engine with no surfaces and write the thread to OUT.json.
# JOB.json: {"model": <ai.extraModels entry> | "<discovered id>", "turns": ["..."],
#            "approvals": {"<tool>": "approve"}, "stubs": {"<tool>": "canned result"},
#            "promptDir": "/abs/dir", "toolTextFile": "/abs/tools.json", "tool": "functions",
#            "memory": false, "timeoutSec": 300,
#            "alwaysAllow": {"shellRules": ["<rule>"], "agent": false}, "stopFile": "/abs/path"}
# alwaysAllow seeds ai.approvals, as if the user had pressed "Always allow" before.
# stopFile: once that file exists the engine presses the stop key (Ai.stopControl) once.
# Exits 0 when every turn finished, 1 when the engine reported an error, 124 on timeout.
# HOME and the XDG dirs are throwaway unless KOOMPI_AI_HEADLESS_KEEP_ENV=1.
set -euo pipefail

[[ $# -eq 2 ]] || { echo "usage: headless.sh JOB.json OUT.json" >&2; exit 2; }
job=$(realpath -- "$1")
out=$(realpath -m -- "$2")
shell_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
[[ -f $job ]] || { echo "headless.sh: no job file $job" >&2; exit 2; }
mkdir -p -- "$(dirname -- "$out")"
rm -f -- "$out"

timeout_sec=$(python3 -I -c 'import json,sys; print(int(json.load(open(sys.argv[1])).get("timeoutSec", 300)))' "$job")
prompt_dir=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get("promptDir", ""))' "$job")
tool_text=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get("toolTextFile", ""))' "$job")

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

if [[ ${KOOMPI_AI_HEADLESS_KEEP_ENV:-} != 1 ]]; then
    mkdir -p "$work/home" "$work/config/koompi" "$work/state/quickshell/user" "$work/cache" "$work/data" "$work/rt" "$work/bin"
    chmod 700 "$work/rt"
    echo greeted > "$work/state/quickshell/user/first_run.txt"
    python3 -I - "$job" "$work/config/koompi/config.json" <<'PY'
import json, sys
job = json.load(open(sys.argv[1]))
ai = {
    "tool": job.get("tool", "functions"),
    "restoreSession": False,
    "memory": {"enable": bool(job.get("memory", False))},
    "approvals": {"shellRules": [], "agent": False},
}
allow = job.get("alwaysAllow") or {}
ai["approvals"] = {"shellRules": [str(r) for r in allow.get("shellRules", [])], "agent": allow.get("agent") is True}
if isinstance(job.get("model"), dict):
    ai["extraModels"] = [job["model"]]
json.dump({"ai": ai, "policies": {"ai": 1}}, open(sys.argv[2], "w"), indent=2)
PY
    # the engine never needs the shell daemon; a missing one is retried, a failing one is not
    printf '#!/usr/bin/env bash\nexit 1\n' > "$work/bin/koompi-shelld"
    chmod +x "$work/bin/koompi-shelld"
    export HOME="$work/home" XDG_CONFIG_HOME="$work/config" XDG_STATE_HOME="$work/state" \
        XDG_CACHE_HOME="$work/cache" XDG_DATA_HOME="$work/data" XDG_RUNTIME_DIR="$work/rt" \
        KOOMPI_SHELLD="$work/bin/koompi-shelld"
fi

if [[ -n $prompt_dir ]]; then
    export KOOMPI_AI_PROMPT_DIR="$prompt_dir"
fi
if [[ -n $tool_text ]]; then
    export KOOMPI_AI_TOOL_TEXT="$tool_text"
fi

export KOOMPI_AI_HEADLESS_JOB="$job" KOOMPI_AI_HEADLESS_OUT="$out"
log="${out%.json}.log"
status=0
if [[ -n ${KOOMPI_AI_HEADLESS_DISPLAY:-} ]]; then
    # already inside a throwaway compositor (a nested test session)
    WAYLAND_DISPLAY="$KOOMPI_AI_HEADLESS_DISPLAY" QT_QPA_PLATFORM=wayland \
        timeout "$((timeout_sec + 30))" qs -p "$shell_root/ai-headless.qml" > "$log" 2>&1 || status=$?
else
    # the services module creates windows, so qs needs a compositor even with nothing to show:
    # a virtual kwin on a bus with no service directories, so nothing of the host's auto-starts
    command -v kwin_wayland > /dev/null || { echo "headless.sh: needs kwin_wayland" >&2; exit 2; }
    cat > "$work/bus.conf" <<'CONF'
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <keep_umask/>
  <listen>unix:tmpdir=/tmp</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
CONF
    printf '#!/usr/bin/env bash\nQT_QPA_PLATFORM=wayland exec qs -p %q\n' "$shell_root/ai-headless.qml" > "$work/inner.sh"
    chmod +x "$work/inner.sh"
    [[ -d $XDG_RUNTIME_DIR ]] || { echo "headless.sh: XDG_RUNTIME_DIR unset" >&2; exit 2; }
    env -u WAYLAND_DISPLAY -u DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u DBUS_SESSION_BUS_ADDRESS \
        timeout "$((timeout_sec + 30))" dbus-run-session --config-file="$work/bus.conf" -- \
        kwin_wayland --virtual --width 1280 --height 800 --no-lockscreen --no-global-shortcuts \
        --exit-with-session "$work/inner.sh" > "$log" 2>&1 || status=$?
fi

# what the run left in the config, for checks on tools that change settings
[[ -f $work/config/koompi/config.json ]] && cp -- "$work/config/koompi/config.json" "${out%.json}.config.json"
[[ $status -eq 124 ]] && { echo "headless.sh: the engine did not exit; log $log" >&2; exit 124; }
[[ -s $out ]] || { echo "headless.sh: no result (exit $status); log $log" >&2; exit 1; }
python3 -I -c 'import json,sys; r=json.load(open(sys.argv[1])); sys.exit(0 if r.get("ok") else (124 if r.get("error","").startswith("timeout") else 1))' "$out"

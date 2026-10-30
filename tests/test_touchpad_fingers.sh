#!/usr/bin/env bash
# libexec/touchpad-fingers, the native messaging host that tells pull to refresh how many
# fingers are on the touchpad, and setup_browser_touchpad, which lets the browsers start it.
#   - it finds the touchpad in /proc/bus/input/devices and passes over a touchscreen, a mouse
#     and a keyboard;
#   - fed kernel input events, it says {"fingers": n} in native messaging frames each time
#     the count changes, and nothing for events that leave it the same;
#   - it exits when the browser closes its stdin;
#   - the manifest names the helper by absolute path and allows only the extension's id,
#     which for an unpacked extension is the sha256 of its path spelled a-p.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$REPO_ROOT/dots/.local/share/koompi/libexec/touchpad-fingers"
failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

command -v python3 > /dev/null || { echo "skip: no python3"; exit 0; }
[[ -x "$HELPER" ]] || fail "touchpad-fingers is not executable"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

PYTHONDONTWRITEBYTECODE=1 python3 -I - "$HELPER" "$tmp" <<'PY' || failed=1
import importlib.machinery, importlib.util, json, os, struct, subprocess, sys, time
sys.dont_write_bytecode = True

helper, tmp = sys.argv[1], sys.argv[2]
loader = importlib.machinery.SourceFileLoader("touchpad_fingers", helper)
spec = importlib.util.spec_from_loader("touchpad_fingers", loader)
tf = importlib.util.module_from_spec(spec)
loader.exec_module(tf)
bad = []

devices = os.path.join(tmp, "devices")
with open(devices, "w") as f:
    f.write("""I: Bus=0011 Vendor=0001 Product=0001 Version=ab83
N: Name="AT Translated Set 2 keyboard"
H: Handlers=sysrq kbd leds event3
B: PROP=0
B: KEY=402000000 3803078f800d001 feffffdfffefffff fffffffffffffffe

I: Bus=0018 Vendor=2c2f Product=0028 Version=0100
N: Name="SNSL0028:00 2C2F:0028 Touchpad"
H: Handlers=event12 mouse2
B: PROP=5
B: KEY=e520 10000 0 0 0 0

I: Bus=0018 Vendor=04f3 Product=2a1c Version=0100
N: Name="ELAN Touchscreen"
H: Handlers=event14 mouse3
B: PROP=2
B: KEY=e520 400 0 0 0 0

I: Bus=0003 Vendor=046d Product=c52b Version=0111
N: Name="Logitech USB Receiver Mouse"
H: Handlers=event7 mouse0
B: PROP=0
B: KEY=ffff0000 0 0 0 0
""")
if tf.touchpads(devices) != ["/dev/input/event12"]:
    bad.append(f"found {tf.touchpads(devices)} where only the touchpad, /dev/input/event12, belongs")

EV = struct.Struct("llHHi")
def key(code, value): return EV.pack(0, 0, 1, code, value)
def report(): return EV.pack(0, 0, 0, 0, 0)
TOUCH, ONE, TWO, THREE = 0x14A, 0x145, 0x14D, 0x14E
two_down = key(TOUCH, 1) + key(TWO, 1) + report()
moving = EV.pack(0, 0, 3, 0x35, 400) + report()          # ABS_MT_POSITION_X, no count change
one_left = key(TWO, 0) + key(ONE, 1) + report()
all_off = key(ONE, 0) + key(TOUCH, 0) + report()
three = key(TWO, 0) + key(THREE, 1) + report()

back_to_two = key(THREE, 0) + key(TWO, 1) + report()
pad = tf.Pad(-1)
got = []
# a read can end mid-event; the rest comes with the next one
for chunk in (two_down, moving, moving, three, back_to_two[:10], back_to_two[10:], one_left, all_off):
    got += pad.feed(chunk)
if got != [2, 3, 2, 1, 0]:
    bad.append(f"counts {got}, wanted [2, 3, 2, 1, 0]")

def frames(data):
    out = []
    while len(data) >= 4:
        n = struct.unpack("=I", data[:4])[0]
        out.append(json.loads(data[4:4 + n]))
        data = data[4 + n:]
    return out

fifo = os.path.join(tmp, "event")
os.mkfifo(fifo)
proc = subprocess.Popen([sys.executable, "-I", helper], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        env={**os.environ, "KOOMPI_TOUCHPAD_DEVICE": fifo, "PYTHONDONTWRITEBYTECODE": "1"})
writer = os.open(fifo, os.O_WRONLY)
for chunk in (two_down, moving, one_left, all_off):
    os.write(writer, chunk)
    time.sleep(0.05)
time.sleep(0.2)
proc.stdin.close()
try:
    out, _ = proc.communicate(timeout=3)
except subprocess.TimeoutExpired:
    proc.kill()
    out = b""
    bad.append("the helper did not exit when its stdin closed")
os.close(writer)
want = [{"ready": True, "fingers": 0}, {"ready": True, "fingers": 2},
        {"ready": True, "fingers": 1}, {"ready": True, "fingers": 0}]
if frames(out) != want:
    bad.append(f"the helper said {frames(out)}, wanted {want}")

for b in bad:
    print("FAIL: " + b, file=sys.stderr)
sys.exit(1 if bad else 0)
PY

# setup_browser_touchpad: a manifest in each browser that has been run, none where not
# shellcheck disable=SC2329,SC2034  # called and read by the setups sourced below
{
    step() { :; }; info() { :; }; ok() { :; }; warn() { :; }; err() { printf '%s\n' "$*" >&2; }
    manifest_add() { printf '%s\n' "$1" >> "$tmp/manifest.list"; }
    DRY_RUN=false
}
XDG_CONFIG_HOME="$tmp/config"
XDG_DATA_HOME="/home/someone/.local/share"
mkdir -p "$XDG_CONFIG_HOME/google-chrome" "$XDG_CONFIG_HOME/BraveSoftware/Brave-Browser"
# shellcheck source=sdata/install/setups.sh
source "$REPO_ROOT/sdata/install/setups.sh" 2> /dev/null || true
declare -F setup_browser_touchpad > /dev/null || fail "setups.sh no longer defines setup_browser_touchpad"
grep -q '^    setup_browser_touchpad$' "$REPO_ROOT/sdata/install/setups.sh" || fail "run_setups does not run setup_browser_touchpad"
setup_browser_touchpad > /dev/null 2>&1 || fail "setup_browser_touchpad failed"
setup_browser_touchpad > /dev/null 2>&1 || fail "setup_browser_touchpad failed the second time"

chrome="$XDG_CONFIG_HOME/google-chrome/NativeMessagingHosts/org.koompi.touchpad.json"
[[ -f "$chrome" ]] || fail "no manifest for Chrome"
[[ -f "$XDG_CONFIG_HOME/BraveSoftware/Brave-Browser/NativeMessagingHosts/org.koompi.touchpad.json" ]] || fail "no manifest for Brave"
[[ ! -e "$XDG_CONFIG_HOME/chromium" ]] || fail "made a config directory for Chromium, which was never run"
[[ "$(wc -l < "$tmp/manifest.list" 2> /dev/null)" == 2 ]] || fail "the second run rewrote manifests that already matched, or the first missed the uninstall list"
# the id this machine's Chrome gave the extension loaded from /home/userx/.local/share/koompi/browser/pull-to-refresh
id_of() { printf '%s' "$1" | sha256sum | head -c 32 | tr '0-9a-f' 'a-p'; }
[[ "$(id_of /home/userx/.local/share/koompi/browser/pull-to-refresh)" == bocompcbabejbmjkmpnjidhlioepdgdd ]] \
    || fail "the id rule no longer gives the id Chrome gave the unpacked extension"
python3 - "$chrome" "$(id_of "$XDG_DATA_HOME/koompi/browser/pull-to-refresh")" <<'PY' || fail "the Chrome manifest is wrong"
import json, sys
m = json.load(open(sys.argv[1]))
assert m["name"] == "org.koompi.touchpad", m
assert m["type"] == "stdio", m
assert m["path"] == "/home/someone/.local/share/koompi/libexec/touchpad-fingers", m
assert m["allowed_origins"] == [f"chrome-extension://{sys.argv[2]}/"], m
PY
grep -q '"nativeMessaging"' "$REPO_ROOT/dots/.local/share/koompi/browser/pull-to-refresh/manifest.json" \
    || fail "the extension does not ask for nativeMessaging, so it cannot reach the helper"
grep -q 'connectNative("org.koompi.touchpad")\|FINGERS_HOST = "org.koompi.touchpad"' \
    "$REPO_ROOT/dots/.local/share/koompi/browser/pull-to-refresh/background.js" \
    || fail "background.js does not start the host the manifest names"

(( failed )) || echo "ok   touchpad fingers: the helper counts fingers from the touchpad alone and the browsers are let start it"
exit $failed

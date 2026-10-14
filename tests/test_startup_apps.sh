#!/usr/bin/env bash
# koompi-startup-apps: an app may not put itself on login without asking (WhatsApp Web came
# back after every reboot through Chrome's own ~/.config/autostart entry).
#   - the first scan keeps what is already there;
#   - a new entry is turned off (its autostart unit masked) and asked about;
#   - Don't allow keeps it masked, Allow unmasks it, and no answer keeps it off;
#   - an entry the app removes is forgotten and unmasked.
# systemctl and notify-send are stubs; nothing touches the real user manager.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$REPO_ROOT/dots/.local/bin/koompi-startup-apps"
failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

for tool in jq flock systemd-escape; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed"; exit 0; }
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/config/autostart"
export XDG_CONFIG_HOME="$tmp/config" LOG="$tmp/systemctl.log" REPLY_FILE="$tmp/reply"
cat > "$tmp/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$LOG"
EOF
# answers with whatever the test put in REPLY_FILE, as notify-send --wait prints the action
cat > "$tmp/bin/notify-send" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$LOG.notify"
cat "$REPLY_FILE" 2>/dev/null
EOF
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:$PATH"

entry() { printf '[Desktop Entry]\nType=Application\nName=%s\nExec=true\n' "$2" > "$XDG_CONFIG_HOME/autostart/$1.desktop"; }
status() { jq -r --arg id "$1" 'if (.allowed | index($id)) then "allowed" elif (.denied | index($id)) then "denied" elif (.pending | index($id)) then "pending" else "none" end' "$XDG_CONFIG_HOME/koompi/startup-apps.json"; }
settle() { local _; for _ in $(seq 1 40); do [[ "$(status "$1")" == "$2" ]] && return 0; sleep 0.1; done; return 1; }

entry fcitx5 "Fcitx 5"
"$TOOL" scan
[[ "$(status fcitx5)" == allowed ]] || fail "the first scan did not keep an entry that was already there"
[[ -s "$LOG" ]] && fail "the first scan masked something: $(cat "$LOG")"

entry chrome-whatsapp "WhatsApp Web"
printf 'deny\n' > "$REPLY_FILE"
"$TOOL" scan
grep -qxF -- '--user mask app-chrome\x2dwhatsapp@autostart.service' "$LOG" || fail "a new entry was not turned off: $(cat "$LOG")"
grep -q 'WhatsApp Web wants to open when you sign in' "$LOG.notify" 2>/dev/null || fail "nobody was asked about the new entry"
settle chrome-whatsapp denied || fail "Don't allow did not stick: $(status chrome-whatsapp)"

entry discord "Discord"
printf 'allow\n' > "$REPLY_FILE"
"$TOOL" scan
settle discord allowed || fail "Allow did not stick: $(status discord)"
grep -qxF -- '--user unmask app-discord@autostart.service' "$LOG" || fail "Allow did not turn the entry back on"

entry slack "Slack"
: > "$REPLY_FILE"
"$TOOL" scan
sleep 0.5
[[ "$(status slack)" == pending ]] || fail "an unanswered entry is $(status slack), want pending"
grep -qxF -- '--user mask app-slack@autostart.service' "$LOG" || fail "an unanswered entry was left on"
asked="$(grep -c 'Slack wants' "$LOG.notify")"
"$TOOL" scan
sleep 0.3
[[ "$(grep -c 'Slack wants' "$LOG.notify")" == "$asked" ]] || fail "an unanswered entry was asked again inside the same session"
"$TOOL" scan --remind
sleep 0.3
(( $(grep -c 'Slack wants' "$LOG.notify") > asked )) || fail "the next login did not ask about the unanswered entry again"

# switched off in its own file (Hidden=true), it keeps its answer and its mask
printf 'Hidden=true\n' >> "$XDG_CONFIG_HOME/autostart/chrome-whatsapp.desktop"
"$TOOL" scan
[[ "$(status chrome-whatsapp)" == denied ]] || fail "an entry switched off in its own file lost its answer: $(status chrome-whatsapp)"
grep -qxF -- '--user unmask app-chrome\x2dwhatsapp@autostart.service' "$LOG" && fail "an entry switched off in its own file was unmasked"

rm "$XDG_CONFIG_HOME/autostart/chrome-whatsapp.desktop"
"$TOOL" scan
[[ "$(status chrome-whatsapp)" == none ]] || fail "a removed entry was not forgotten"
grep -qxF -- '--user unmask app-chrome\x2dwhatsapp@autostart.service' "$LOG" || fail "a removed entry kept its mask"

grep -q 'Slack' <<< "$("$TOOL" list)" || fail "list does not show the entries"

(( failed )) || echo "ok   startup apps: new ones are off until allowed; answers stick; removed ones are forgotten"
exit $failed

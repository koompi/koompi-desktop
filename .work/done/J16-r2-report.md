# J16 round 2: report

The harness refused to let me write a report .md ("Subagents should return findings as text"), so there is no `.work/J16-report.md`. This message is the report. Evidence, renders and tools are in `/home/userx/.tmp/J16-handoff/round2/` (no report file there).

Branch `worktree-agent-abdbce54fdf139a96`, base `686e9aa20` (confirmed with `git log --oneline -1` before any edit). HEAD `51cd75d35`, tree clean, no trailers, no `--no-verify`.

```
a252ea08d displays: saved rules follow the display, not the port
3e43e4dc9 displays: a switched rate waits for Keep and goes back on its own
17fc78da1 displays: a save that cannot read the monitors writes nothing
faeb3fea8 cli: koompi help display lists rate, keep and revert
e803d2fda displays: keep saves only a rate the monitor is still running
092f7f3aa displays: rate names the rate it switched to, as it was typed
f26446b80 settings: Displays asks Keep or Revert after a refresh-rate switch, and shows what the tool says when it fails
c968e24cc displays: the rules program reuses JQ_MODE instead of a second copy
4fa049903 tests: the escape case runs koompi-displays' own lua validation
51cd75d35 brightness: a monitor that outlives its screen no longer logs a TypeError
```

## What changed

**1. Saved rules belong to a display** (`dots/.local/bin/koompi-displays`, `rules_program` :31, `persist_layout` :48)
- Each connected monitor is saved as `output = "desc:<description>"`, escaped for a Lua string (`\` and `"`).
- Rules of displays not connected now are kept verbatim (first in the file); a port-keyed rule from an older file is replaced when its port is connected and kept until then.
- The header has no timestamp, so the same monitors write the same bytes.
- Description empty, shared by two monitors, or with a control character: keeps the port (decision 1 below).
- `transform` is written. Measured in nested Hyprland 0.56.2 (`nested/probe4-transform-port-vs-desc.txt`): a rotated user rule kept `transform = 1` when `monitors.lua` added a same-named port rule, and lost it (0) when the new rule was `desc:`-keyed, because only the last matching rule applies. Without the line, the first save would un-rotate a rotated monitor.
- `persist_layout` returns 1 itself on a read or write failure. It runs under `if !` in `keep`, where `set -e` is off; the old shape wrote a file of only old rules when `hyprctl` failed (commit `17fc78da1`, test fails on the prior commit).

**2. Labels** (`DisplaysConfig.qml:44-51`): whole hertz, decimals only for rates that round to the same integer as another listed rate. HDMI-A-1 shows `75 Hz`, `60 Hz`, `59.94 Hz`. Option values stay exact. The line above the rows says `@75Hz` too.

**3. Confirm or revert**
- **Where the timer lives:** `koompi-displays _expire` (`cmd_expire` :134), a process in its own session (`setsid -f`), armed by `arm_pending` (:144) **before** the mode changes.
- **Why:** Settings is its own `qs` process and `settings.qml` quits it on close (`onClosing: Qt.quit()`); `pageLoader` also destroys the page when the person changes page. A QML timer dies with whichever holds it, and a black screen cannot be clicked.
- The wait counts 0.25 s sleeps, so a clock step cannot stretch it. The record is `$XDG_RUNTIME_DIR/koompi-displays/pending`; keep, revert and the timer take it by `mv`, so exactly one acts.
- `rate` (:200) arms, applies, waits for the compositor's own report, prints `{"monitor","rate","previous","deadline","seconds"}`, saves nothing. `keep` (:235) re-checks the compositor still reports the new rate (a config reload drops run-time rules; measured), saves, and puts the old mode back if it cannot. `revert` (:252).
- `place` and a second `rate` are refused while one waits; an expired record (timer killed) is undone before the next command.
- Page: bar under the Refresh rate row, **Keep this refresh rate?**, `75 Hz now. Going back to 60 Hz in 12 s`, Keep and Revert. The countdown is display only; at 0 the page also asks `revert` (idempotent). `Component.onDestruction` asks for it at once. Window close is tested; leaving the page by the Loader is by its source swap and is not exercised.

**4. Errors reach the page:** `modules/settings/DisplaysCommand.qml` (new, 52 lines) runs the tool as a `Process` and settles when the exit and both streams have arrived. The message sits under the row it came from, for `rate`, `keep`, `revert` and `place`; one at a time, cleared by the next command.

**5. CLI** (`cli/src/main.zig:19`): usage lists `place`, `rate`, `keep`, `revert` (rate alone saves nothing). Built with `setup_koompi_cli`'s flags (cache, global cache, prefix outside the checkout, `-Doptimize=ReleaseSafe`): `zig build test` passed; `koompi help display` prints the four lines.

**6. Brightness** (`services/Brightness.qml:70`): `monitor.screen?.name ?? ""`, with `tests/test_brightness_screen_gone.sh`.

**8. Comments:** both test headers are one line, narrative blocks gone, new files have none beyond one-line whys.

Files outside your list, named: `DisplaysCommand.qml` (needed to see exit status), `tests/displays-hyprctl` and `tests/displays-monitors.json` (one stateful stub and the founder's monitors, shared by three tests), `tests/test_displays_desc.sh`, `tests/test_brightness_screen_gone.sh`.

## Tests: failing on dev, passing after

On dev = the new test run against dev's file (`686e9aa20`) in a throwaway mirror (`tools/ondev*.sh`).

| Test | On dev | After |
| --- | --- | --- |
| `test_displays_desc.sh` (new, script) | 19 `FAIL`: `the layout is not one desc: rule per display`, `old port rules of connected monitors stayed, or rules of unplugged ones went`, `a second save with the same monitors changed the file`, `unplugging the HDMI display lost its rule or doubled eDP's: "eDP-1"`, `a display with no description was not saved by its port` | 5 PASS, `ok   displays desc: ...`, exit 0 |
| `test_displays_rate.sh` (rewritten, script) | 28 `FAIL`: `rate saved a layout before it was kept`, `keep exited 1: usage: ...`, `revert left the monitor at 74.97`, `no answer for 6 s and the monitor was not put back`, `place exited 0 while a rate change was waiting`, `keep wrote a layout it had not read`, `keep saved a rate the monitor was not running` | 13 PASS, `ok   displays rate: switched, kept, reverted, expired and refused as above`, exit 0 |
| `test_displays_rate_row.sh` (rewritten, page in KWin) | `FAIL its labels are whole hertz...`, `FAIL step 1 never happened` (no bar), `FAIL: monitors.lua is not exactly the layout of the one rate that was kept`, `FAIL: closing Settings with a change waiting left the monitor on 60.00000` | 24 PASS, `PROBE DONE`, `ok   displays page: ...`, exit 0 |
| `test_brightness_screen_gone.sh` (new, KWin) | `FAIL: a screen that went away logged: WARN scene: @services/Brightness.qml[70:-1]: TypeError: Cannot read property 'name' of null` | `ok   brightness: a screen that goes away leaves no TypeError` |
| `test_displays_persist.sh` (not mine, untouched) | passes | passes (its monitors have no description, so they keep their ports) |

**Timeout path** (script test, 6 s window): `rate` returns with one eval in the log, so the revert is not the caller's; no answer; the second eval is the old mode (`1920x1080@60`), the stub monitor is back at 60, `monitors.lua` is byte for byte what it was, no record is left, and `keep` afterwards is refused. The page test shows the same through the real page.

**Window close** (page test): the old rate is back less than 4 s after Settings closes. The test's timer is 8 s. A page without `Component.onDestruction` fails that check (state changed 8 s after the close, `mutant-page-no-destruction.txt`).

**Mutants** (`mutants-script.txt`): timer does nothing, no refusal while waiting, keep without the rate check, rate saving at once, merge dropped, port keys always, transform not written: all 7 killed. A gsub that leaves the quote bare makes the script's own `luac -p` reject the file.

## The `desc:` proof (nested Hyprland 0.56.2 in headless KWin, private bus, HOME, runtime dir, through heavy.sh; `nested/desc-proof.txt`, `tools/nested.sh`, `tools/steps-desc.sh`)

1. The file `koompi-displays` writes for a description `ACME "Pro" \ 27`, transform 1: loaded by the running compositor, `hyprctl configerrors` empty, output untouched (other display).
2. A `desc:` rule whose description equals the output's own, loaded after the catch-all, applies: `1280x800` at `0x0` scale 1 becomes `1000x700` at `300x0`, scale 1.67 (snapped), `transform` 1, read back from `hyprctl monitors -j`.
3. Control `desc:NOPE`: no change.
4. A run-time port rule (what `rate` sends) wins over the saved `desc:` rule until `hyprctl reload`, which restores the saved one.

**Limit, not hidden:** nested outputs have an **empty description** (Wayland and headless), so step 2 matched on the empty string. A rule for `desc:BOE 0x0CE0` against a monitor reporting that exact string I could not run. To check on the seat with the founder's word: after a Keep, `hyprctl monitors -j | jq -r '.[].description'` must equal the text after `desc:` in `~/.config/hypr/monitors.lua`.

Also measured: nested Wayland outputs ignore the `@R` of a rule (`@75.00` and `@50.00` both leave 60) and list no modes. The rate flow is proven with the real script and the real page against a stateful `hyprctl`, not against Hyprland.

## Screens (`renders/<case>/*.png`, `*-crop.png` is the window)

Real `DisplaysConfig` in a 1100x750 window, real `koompi-displays`, stateful `hyprctl`, headless KWin; `tools/render*.sh`. I looked at every file:
- `two-1920x1200`, `two-1366x768`: rows, bar, kept, rate error, place error (dark).
- `one-1920x1200`, `one-1366x768`: HDMI alone: rows, bar, kept, rate error (no Position row, no gap).
- `two-1366x768-light`: all five, light palette (matugen).

Seen: a rounded card under the pills with a clock icon, the question in bold, `75 Hz now. Going back to 60 Hz in 12 s` falling one a second, Keep and Revert. Rate and Position pills are dimmed while it waits. After Keep the bar is gone and the buttons are back. The error is small, in the error colour, directly under its row, one at a time. No overlap, clipping or wrapping at either width, in either palette. Render `qs.log`: 0 `TypeError`, `ReferenceError`, `Binding loop`, `Cannot assign`.

Seen and not fixed: while the question is up, the selected pill is dimmed with the rest and nearly unreadable in the light palette (shared `RippleButton` disabled style, 40% opacity); the bar names the new rate for that reason. Not looked at: Khmer (no translations yet), a real 1.25-scale monitor, the live seat.

## Full suite

`heavy.sh env -u HYPRLAND_INSTANCE_SIGNATURE NO_COLOR=1 ./tests/run.sh` on `51cd75d35`, nothing changed while it ran:

```
127 passed, 4 skipped, 0 failed
skipped: test_bar_keys.sh test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh
```

The four are the baseline's. `test_update_now_runs.sh` passed. My six, `test_file_length`, `test_private_bus`, `test_nested_hyprland_quiet` are `ok`. Whole output: `suite.txt`.

## Decisions you may overrule

1. Empty, shared or unprintable description keeps the port (two such monitors would otherwise get two rules that both match both).
2. `transform` is saved. `mirror`, `vrr`, `bitdepth`, `cm`, `icc` of a user's own rule for that display are dropped once a `desc:` rule exists (last matching rule wins; `monitors -j` only reports `mirrorOf` for those). Proposed: leave it, or carry `mirror = "<mirrorOf>"` (five lines).
3. Clicking the already-selected rate does nothing; round 1's pin-by-click is gone. From a terminal: `koompi display rate HDMI-A-1 60`, then `koompi display keep`.
4. `KOOMPI_DISPLAYS_CONFIRM_SECONDS` (default 15) exists for tests only.
5. `setsid` (util-linux) is a new assumption of this tool; `koompi-reload` and `koompi-quicklook` already use it. No package list changed.

## For J40 and the vault

Strings: `Keep this refresh rate?`, `%1 now. Going back to %2 in %3 s`, `Keep`, `Revert`, `The display tool did not run`, plus round 1's `Refresh rate`, `%1 Hz`.

Gotchas: Hyprland applies only the last matching monitor rule (a `desc:` rule does not inherit a port rule's `transform`). `hyprctl reload` drops run-time rules. Nested outputs have no description and ignore a rule's refresh rate. A Quickshell `Process` reports exit and each collector's end separately, in any order. `Component.onCompleted` on a `ShellRoot` fails with "Non-existent attached object" (use a Timer). An inline `component X: Y` cannot see the file's ids.

## Not done, exact reasons

- Non-empty `desc:` match in a compositor: no nested output has a description.
- Any real mode change: nested outputs ignore `@R`; the live seat is yours.
- `.work/J16-report.md` and a report in the handoff dir: the harness refused report files.

## Disclosures

- Early on I ran `hyprctl version` once with `HYPRLAND_INSTANCE_SIGNATURE` set, so it asked the live Hyprland (read only, nothing changed). Every later `hyprctl` was a stub or inside a nested session.
- I ran `tests/test_services_qml_bugs.sh` once outside `heavy.sh`, in a loop of static tests (it starts a brief offscreen `qs`). Everything with a compositor after that went through `heavy.sh`.
- `matugen` ran once with `-c` on a scratch config. A 145 MB disassembly I wrote to `/tmp` is deleted. Kept test dirs I printed were removed by exact path. Nothing under `~/.config`, `~/.local` or `/etc` was written.
- No `Claude-Session` trailer (your contract and the user's rule say no agent trailer).

## Handoff dir `/home/userx/.tmp/J16-handoff/round2/`

`script-tests-on-dev.txt`, `page-on-dev.txt`, `brightness-on-dev.txt`, `test_displays_*-after.txt`, `page-after.txt`, `brightness-after.txt`, `suite.txt`, `mutants-script.txt`, `mutant-page-no-destruction.txt`, `nested/` (proof and probes), `renders/`, `tools/` (they reference my scratch dir `/home/userx/.tmp/j16r2.F9NF5T` and my worktree path; edit `REPO` and `S` at their tops).
Re-run: the three script tests directly; `heavy.sh env -u HYPRLAND_INSTANCE_SIGNATURE bash tests/test_displays_rate_row.sh` and `tests/test_brightness_screen_gone.sh`; `cd cli && zig build test --cache-dir /tmp/c --global-cache-dir /tmp/g --prefix /tmp/o`.

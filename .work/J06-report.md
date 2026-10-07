# J06 report: stopped on a product decision, no code change

Branch `worktree-agent-a896aebb39304401a` (worktree `.claude/worktrees/agent-a896aebb39304401a`), re-pointed at `dev` `d75bca56c`, **zero commits**. `dev` has moved to `ad6b362f8` since; the three commits after `d75bca56c` touch Settings and bookkeeping, not `general.lua`, `koompi-displays` or the Displays page.
(This file lives in the worktree's gitignored `.work/`; copy it to `.work/J06-report.md` in the main checkout. Supporting files are in `.work/J06-evidence/`, the Jev request is `.work/J06-jev-request.json`. A copy of all three is in `/home/userx/.tmp/J06-handoff/`, in case an unchanged worktree is cleaned up.)

## Why I stopped

The brief asks for `highrr`, "the highest refresh rate at the preferred resolution". On the installed Hyprland, `highrr` is not that: decoded from the binary, it ranks every mode by refresh rate first, and replayed over the founder's own HDMI monitor's mode list it puts 1024x768@75.03 ahead of 1920x1080@74.97.
The alternatives that fit the files I own (`highres`, or leaving `preferred`) each trade something, and the exact solution needs a file J06 does not own.
That is a design choice, so per the vault note (`feedback/jev_decides.md`: "Workers never call Jev. A decision met mid-contract is a stop-and-report to the lead") I stop here and hand over the framed decision instead of picking.

## What I measured

All of it on this machine, nothing against the live compositor (sysfs reads, `edid-decode`, `objdump`, a private-runtime-dir nested Hyprland).

1. **What `hl.monitor` mode accepts.** `/usr/share/hypr/stubs/hl.meta.lua:580` types it `string` and says no more. The installed `/usr/bin/Hyprland` 0.56.2 exports `Config::CMonitorRuleParser::parseMode`; disassembled, it accepts a prefix `pref` (preferred), `highrr`, `highres`, `maxwidth`, or `WxH[@R]`, and stores the special ones as resolution (-1,-1), (-1,-2), (-1,-3). There is no keyword for "highest refresh at the preferred resolution".
2. **What `highrr` does.** `CMonitor::applyMonitorRule` copies every listed mode, `std::sort`s it with the comparator at `0x71d890` (`.work/J06-evidence/highrr-comparator.s`), keeps the first three, and tries them best first (the helper at `0x722d00` inserts them reversed onto a stack that is popped from the back; `preferred` sits at the bottom as the last resort). The comparator is: `a` before `b` if `a.refreshRate > b.refreshRate` (uint32, mHz, no rounding); if the two differ by less than 1 mHz, the larger resolution wins. **Resolution only breaks exact ties.**
3. **The founder's HDMI monitor** (`WAM 9088`, `edid-decode /sys/class/drm/card0-HDMI-A-1/edid`, saved in `hdmi-edid.txt`): preferred `1920x1080@60.00`; also `1920x1080@74.97` and the legacy VESA 75 Hz timings `1024x768@75.03`, `1280x1024@75.02`, `1152x864@75.00`, `800x600@75`, `640x480@75`. The kernel's mode list agrees (`hdmi-sysfs-modes.txt`: `1024x768` three times, `1280x1024` twice).
4. **Replication** (`sim.cpp`, same libstdc++ `std::sort`, the decoded comparators, the monitor's EDID-derived 30 modes; **not run inside Hyprland**, the nested output lists no modes, see 7):

```
== HDMI-A-1 (WAM 9088, EDID-derived, 30 modes)
highrr, first three tried in order:
  1024x768  @ 75.029 Hz  (established)
  1280x1024 @ 75.025 Hz  (established)
  1152x864  @ 75.000 Hz  (established)
highres, first three tried in order:
  1920x1080 @ 74.973 Hz  (DTD 2)
  1920x1080 @ 60.000 Hz  (DTD 1, preferred)
  1920x1080 @ 59.940 Hz  (CTA VIC 16 variant)

== eDP-1 (BOE 3296, one mode)
highrr, first three tried in order:
  1920x1200 @ 60.003 Hz  (DTD 1, only mode)
highres, first three tried in order:
  1920x1200 @ 60.003 Hz  (DTD 1, only mode)
```

   So `highrr` as the catch-all would drop this monitor to 1024x768; and since `1920x1080@74.97` is not among the three modes `highrr` keeps, the finding does not depend on the try order I decoded. The legacy 75 Hz timings are a standard EDID bitmap; I only have this one external EDID, so "many monitors" is reasoning, not measurement. The internal panel claim in the brief holds: one mode, 1920x1200@60.003, so every keyword resolves to it.
5. **`highres`** (comparator `0x71d7e0`, `highres-comparator.s`): a mode strictly larger in both dimensions sorts first, equal size sorts by higher refresh. It gives `1920x1080@74.97` here. Two data-dependent costs, neither measurable on this machine: a display whose largest listed mode is not native (a projector that lists 1080p over a WXGA panel) is moved off native; and modes larger in only one dimension (3840x2160 against 4096x2160) compare equal, so their order is the list order (a synthetic 4K TV list happened to pick `3840x2160@60`, `sim2.out`, which shows nothing either way).
6. **A saved per-monitor rule wins over the catch-all**, verified in the nested harness in both orders (`probe-results.txt`): catch-all `highrr` plus named `WAYLAND-1 1000x700@60 scale 1`, in either order, ends `1000x700@60.0 scale 1`. In the repo, `hyprland.lua:41-43` requires `~/.config/hypr/monitors.lua` after `hyprland.general`. That file is written by `dots/.local/bin/koompi-displays place`, which persists `mode = WxH@<current rate, 0.1>` for **every** monitor at placement time. Hyprland resolves a saved `WxH@R` by nearest width, then nearest height, then nearest rate (comparator `0x71d650`), so a persisted `1920x1080@75.0` lands on the listed 74.97 mode, not a synthesized one. Two consequences: a user who has ever used the placement dropdown keeps the rate they had then whatever the catch-all says; and Settings > Displays (`modules/settings/DisplaysConfig.qml`) shows the rate read-only and has no refresh-rate chooser, so the catch-all is the only default lever today.
7. **Proving a rule loads.** The lead's `hyprshot.sh` appends its own `output = ""` rule after the repo config, so it never exercises the repo's catch-all; I used a scratch copy without that line (`hyprmon.sh`, `go.sh`). In it the shipped config has an empty `hyprctl configerrors`; `highrr` and `highres` load clean; `mode = "banana"` shows `hyprland.lua:43: hl.monitor: error applying field 'mode'` (negative control). The nested Wayland output reports `availableModes: []`, so **which mode a keyword picks cannot be exercised there**, only that it loads. Without any compositor, `Hyprland --verify-config -c file.lua` (private `XDG_RUNTIME_DIR`) prints `config ok` / exit 0 for `highrr` and `highres` and exit 1 with the same error for the bad value (`verify.sh`). It also takes the whole shipped config: `verify-full.sh` stages `dots/.config/hypr` into a temp HOME (`custom/` is generated there by `hyprland.services`, never linked, the repo stays clean) and prints `config ok`, exit 0, on the shipped tree, and with a bad catch-all appended `hyprland.lua:47: hl.monitor: error applying field 'mode'`, exit 1. That is the cheap, compositor-free "the rule loads" check for whichever keyword ships. No test in `tests/` uses it today.

## Re-verify in four commands

The addresses are for the installed build (`hyprland 0.56.2-3`, BuildID `97bb00da54eae3fefc488f1b75695e602455f9f2`).

```
edid-decode /sys/class/drm/card0-HDMI-A-1/edid | grep -E ' Hz '       # the monitor's modes (passive sysfs read)
objdump -d -C --no-show-raw-insn --start-address=0x71d890 --stop-address=0x71d922 /usr/bin/Hyprland   # the highrr comparator
sim=$(mktemp) && g++ -std=c++20 -o "$sim" .work/J06-evidence/sim.cpp && "$sim"   # the replication table above
bash .work/J06-evidence/verify-full.sh                                 # edit its `repo=` line; prints "config ok", exit=0 (no compositor)
```

## The decision, framed (not run)

`.work/J06-jev-request.json` is the request body. The command that clears the blocker, run by the lead:

```
~/.claude/bin/jev-decide /home/userx/workspace/koompi/koompi-desktop/.claude/worktrees/agent-a896aebb39304401a/.work/J06-jev-request.json
```

| Option | Change | Verified here | Not verifiable here |
| --- | --- | --- | --- |
| `keep_preferred` | none in J06; F8 becomes a refresh-rate row in Settings > Displays writing the saved rule (`DisplaysConfig.qml`, `koompi-displays`, `tests/test_displays_persist.sh`), a Phase 1 job | cannot regress any display | needs the founder to pick 75 Hz once |
| `highres_catchall` | `general.lua:4` `"preferred"` to `"highres"`, plus `tests/test_monitor_default.sh` asserting the keyword and running `Hyprland --verify-config` on the shipped config; fails on `preferred` | 1920x1080@74.97 on the HDMI monitor, unchanged laptop panel (replication) | projector / non-native-largest displays |
| `lua_exact_handler` | new `hyprland/refresh.lua` (+ a require in `hyprland.lua`; `general.lua` is at its 371-line ratchet), `monitor.added` and `config.reloaded` handlers that raise the rate only at the running resolution and skip monitors with a saved rule; a test feeding the real mode list to `lua5.4` (installed here) | the selection function on the real mode list | the Lua `available_modes` element format and event payload, a second modeset on every connect, ordering against the reload re-apply, any multi-mode output |
| `highrr_catchall` | one word | loads clean | measured: sets 1024x768 on the founder's monitor |

My proposed answer is `keep_preferred`: nothing in J06 can regress a user. The cost is that F8 stays open until the Displays row lands and the founder picks 75 Hz once. The helper half is testable here against stubbed `hyprctl` JSON, as `tests/test_displays_persist.sh` does; the QML row would show a single rate in the nested harness because its output lists no modes. `highres_catchall` is the fallback if the founder wants an automatic default and accepts the projector risk.
For the founder's own monitor today, a one-line `hl.monitor` rule in his `~/.config/hypr/custom/general.lua` would give 75 Hz with no package change, but only if `monitors.lua` has no rule for `HDMI-A-1` (it is loaded later and wins). That is his call; I did not read or write `~/.config`.

Once the pick is known, send it back to this worker (it keeps the harness and the evidence) or re-dispatch with the option name; the files, the test and the commit message are as in the table.
For the vault's `koompi_de_gotchas` (the lead's to write, whatever the pick): Hyprland 0.56.2 `highrr` ranks every listed mode by refresh first, so a monitor that lists legacy 75 Hz timings (1024x768, 1280x1024) is set to one of those; and `hyprshot.sh` appends its own `output = ""` rule, so it never runs the repo's catch-all.

## Confirmation I could not run

The compositor's own mode list for the HDMI monitor, which would turn my EDID-derived list into the real one. Two read-only ways, both on the live session, which the contract forbids me, so I did neither:

```
hyprctl monitors -j | jq '.[] | select(.name=="HDMI-A-1") | .availableModes'
grep -a 'drm: Mode' /run/user/1000/hypr/*/hyprland.log      # aquamarine logs "drm: Mode N: WxH@R.RRHz" at start, no IPC
```

What narrows the kernel list before Hyprland ranks it: `libaquamarine.so.14` carries one filter string, "drm: Skipping mode {} because it's interlaced". The EDID of this monitor lists no interlaced mode, so the ranked list should equal the 30 modes I used. If the live list lacks `1024x768@75.03` and `1280x1024@75.02`, the `highrr` finding does not hold for this monitor and the replication above should be rerun on the real list (`sim.cpp`, one table).

## Full suite

`unset HYPRLAND_INSTANCE_SIGNATURE; NO_COLOR=1 ./tests/run.sh` on the unchanged branch (`d75bca56c`):

```
105 passed, 4 skipped, 1 failed
skipped: test_bar_keys.sh test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh
failed: test_update_now_runs.sh
```

The one failure is the flake J15 is filed for, and it is not mine: `FAIL: Update now opened no window (hyprctl clients is empty)`, the exact message in `jobs/J15-update-now-flake.md`, while other workers had nested sessions running. Rerun alone on the same tree straight after: `ok   Update now opened a floating wezterm window ...`, exit 0 in 7 s. The branch has no change against `dev`, so it fails on `dev` too, intermittently (J15's evidence: 3 failures in 11 runs on `dev` at `e6d563717`).
A third sample for J15 is in `.work/J06-evidence/j15-sample/` (the dirs my run kept were copied there, then deleted): `koompi.ran` says `update`, so the terminal was launched; the wezterm GUI log has the portal warning at 22:07:09 and the broken pipe at 22:08:12, after the 60 s wait; `qs.log` shows both probe PASS lines, so the compositor, the shell and the click all worked; the harness stdout ends with `(EE) could not connect to wayland server`, which I did not compare with a passing run.
`skipped` are the same four as the lead's baseline (live-seat or bench-only; `test_bar_keys.sh` and `test_globalmenu.sh` skip because the signature is unset, as the contract requires).

## Disclosures

- Scratch files (harness copy, probes, binary dumps) are in `/home/userx/.tmp/tmp.Q4aQhN0iAz/` and copied into `.work/J06-evidence/`; nothing was written under `~/.config`, `~/.local` or `/etc`.
- The first `e2_named_after` nested probe printed no monitor line (a timing miss before the monitor was listed); the diagnostic rerun and the opposite order both gave `1000x700@60 scale 1`, and `probe-results.txt` shows the reruns.
- `HYPRLAND_INSTANCE_SIGNATURE` was set in my shell; every harness and the suite ran through scripts that unset it first.
- I read `dots/.local/bin/koompi-displays`, `DisplaysConfig.qml` and the sysfs EDID of both connected outputs; I did not run `modetest` or any ioctl against the DRM device.
- I read the last two lines of `~/.claude/jev-decisions.jsonl` and `feedback/jev_decides.md` only to copy the question format and learn the worker rule; I did not run `jev-decide`.

# J16: choose a monitor's refresh rate in Settings > Displays

Audit: `docs/design/ux-audit-2026-10-07.md` section 5, F8, and decision D7 in section 7 (`J06_catchall keep_preferred p=0.79`). Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.
Files owned: `modules/settings/DisplaysConfig.qml`, `dots/.local/bin/koompi-displays`, `tests/test_displays_persist.sh` (or a new `tests/test_displays_rate.sh`), the Displays lines of `docs/manual/*` if any describe the page.

## Evidence

- The catch-all `hl.monitor` stays `mode = "preferred"` (D7): Hyprland 0.56.2's `highrr` ranks refresh before size and would run the founder's HDMI monitor at 1024x768@75.
- The founder's HDMI-A-1 runs 1920x1080@60 and lists 1920x1080@74.97, 1920x1080@60.00 and 1920x1080@59.94 at its resolution, plus legacy lower-resolution modes. The laptop panel lists one mode, 1920x1200@60.
- `koompi-displays place` hot-applies through `hyprctl eval "hl.monitor({...})"` and persists every monitor's current `WxH@R` to `~/.config/hypr/monitors.lua`, which loads after the catch-all and wins over it. `DisplaysConfig.qml:108-109` shows the rate read-only; `:150-153` calls `koompi-displays place`.

## Do

1. `koompi-displays rate <monitor> <hz>`: applies `<current WxH>@<hz>` to that monitor (same `hyprctl eval hl.monitor` form, position and scale unchanged) and persists the layout through the same validated write-then-mv step `place` uses. Factor that persist step into one function both subcommands call; do not copy it. Refuse a rate the monitor does not list at its current resolution, with a message and non-zero exit.
2. A "Refresh rate" row per monitor in Displays, shown only when the monitor lists more than one rate at its current resolution. Options are those rates, deduplicated after rounding to two decimals and shown as "75 Hz" or "59.94 Hz", highest first, with the current one selected. Never offer a rate at another resolution. Selecting one calls `koompi-displays rate`, by absolute path as `place` does, then refreshes the page's monitor data.
3. Tests, both failing on `dev`:
   - script: with the existing hyprctl stub fed the founder's real mode list, `rate HDMI-A-1 74.97` issues one `hl.monitor` eval with `mode = "1920x1080@74.97"` (or the closest form Hyprland matches; say which and why), keeps position and scale, and writes a `monitors.lua` that passes the existing validation; `rate HDMI-A-1 75.03` is refused (that rate exists only at 1280x1024 and 1024x768).
   - page: a probe that feeds the Displays page the founder's monitors and asserts the row's options for HDMI-A-1 are 74.97 and 60 (and 59.94 if it survives dedup), and that eDP-1 has no row.

## Acceptance

- Test before/after output for both.
- `shellshot.sh` renders of the Displays page with the stubbed monitors, at 1920x1200 and 1366x768, looked at in full.
- Full suite: 0 failed (`test_update_now_runs.sh` is a known flake; say if it is the only failure and that it passes alone).

## Out of scope

- Applying a rate on the live seat: the lead does that only with the founder's word.
- Resolution or scale choosers, VRR, a drag canvas.
- The nested harness cannot exercise mode choice (its output has no modes, and `hyprshot.sh` adds its own monitor rule); do not try to prove the hot-apply there.

## Round 2 (lead, 2026-10-07; round 1 merged)

Files owned:
- `dots/.local/bin/koompi-displays`
- `modules/settings/DisplaysConfig.qml`
- your two tests
- `services/Brightness.qml` (one line)
- `cli/src/main.zig:19` (one usage string)
- whatever small piece the confirm step needs, named in the report

Decided:
- `J16_persist_scope desc_keyed_merge p=0.99 (jev-1.13.0)`
- `J16_rate_labels round_unless_ambiguous p=0.68 (jev-1.13.0)`
- `J16_confirm_revert confirm_or_revert p=1.0 (jev-1.13.0)`

1. **Saved rules belong to a display, not a port.**
   - `persist_layout` writes `output = "desc:<description>"` for each connected monitor. The founder's are `BOE 0x0CE0` and `WAM HDMI 18250023`.
   - It keeps every rule in the old file for a monitor that is not connected now.
   - A port-keyed rule from an older file is replaced when its port is next seen connected, and kept until then.
   - Escape descriptions for a Lua string: `validate_lua` must still pass with a quote or a backslash in one.
   - Prove in the nested harness that a `desc:` rule in the Lua config matches: read back a property the rule set.
   - Idempotent: two runs with the same monitors write the same file.
2. **Labels:** whole hertz ("75 Hz"), unless two listed rates round to the same integer; those show two decimals ("59.94 Hz" beside "60 Hz").
3. **Confirm or revert.**
   - After a switch, ask "Keep this refresh rate?" with a 15 s countdown.
   - Save only on Keep. Revert to the previous mode on Revert, on timeout, and if the Settings window closes.
   - The revert must not depend on anyone seeing or clicking anything: the screen may be black.
   - Put the timer where it survives the page, and say where and why.
   - Test the timeout path: no answer means the old rate is back and `monitors.lua` is unchanged.
4. **Errors reach the page.** Replace `execDetached` with something that sees the exit status, and show the tool's message under the row when it fails. Do this for `place` too.
5. `cli/src/main.zig:19`: the usage lists `display rate` as well. Build the CLI the way its own check does.
6. `Brightness.qml:70` reads `monitor.screen.name` with no null check. A monitor that goes away (unplug, or teardown in your renders) logs a TypeError. Guard it.
7. Look at the screen again: 1366x768 and 1920x1200, one and two monitors, the countdown visible, and the error line.
8. Comments break CONTRACT.md line 19: the headers of `test_displays_rate.sh` and `test_displays_rate_row.sh` (20 comment lines each) become one line each, and narrative blocks inside go.

FYI: the lead fixed `test_popup_clamp.sh` and `test_bar_keys.sh` (your open point 4). `test_private_bus.sh` now fails on any `kwin_wayland` outside a private bus.

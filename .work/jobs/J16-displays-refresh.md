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

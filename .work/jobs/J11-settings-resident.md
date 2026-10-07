# J11: Settings opens in the running shell

Audit: `docs/design/ux-audit-2026-10-07.md` sections 3.10 and 5 (F5). Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first. Depends on J07's lazy-surface component being merged.

## Evidence

- Live seat: `Super+I` to the Settings window took about 1.1 s; `dots/.local/bin/koompi-settings` starts a fresh `qs -p settings.qml` process each time and kills it to close (`:24-29`).
- Every singleton the page reads (`Config`, `Appearance`, services) is already loaded in the running shell.

## Do

1. The running shell hosts Settings as a lazily built floating window (J07's component, keep-warm included), opened and closed by an IPC target (`settings open|close|toggle`, plus `page <name>` for the existing page argument).
2. `koompi-settings` asks the running shell over IPC; if the shell is not running or the call fails, it falls back to today's standalone `qs -p settings.qml`, so Settings still opens when the shell is down.
3. Window identity: keep whatever class/title rules in `dots/.config/hypr/hyprland/rules*.lua` match Settings today (float, size, centre), or update them to match the new window.
4. `settings.qml` stays a valid standalone entry point (the fallback), sharing the page components rather than duplicating them.
5. **Measure.** In the nested Hyprland harness: `Super+I` path (`koompi-settings` via `hypr:hl.dsp.exec_cmd(...)`) to the window being listed by `hyprctl clients -j`, cold and warm, three runs each, before and after.
6. **Test.** `koompi-settings` with `qs` shadowed: uses IPC when the shell answers, falls back when it does not. A headless test that the IPC opens a window.

## Acceptance

- Timings before/after; target ≤ 200 ms warm, ≤ 400 ms cold.
- Hyprshot screenshot of Settings opened through `koompi-settings`.
- Full suite: no new failures.

## Out of scope

- Settings content and naming (Phase 3).

# J01: the update badge leaves the panel button; bar popups stay on screen

Audit: `docs/design/ux-audit-2026-10-07.md` section 3.1, rows B1 and B5. Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.

## Evidence

- `modules/koompi/bar/BarContent.qml:201` is the right-sidebar `RippleButton`; `:264` puts `UpdateBadge` inside its `indicatorsRowLayout`. On the live seat it reads `384`.
- `modules/koompi/bar/UpdateBadge.qml:66-72`: left click dispatches `runUpdate`, a full `koompi update` in a terminal. A click aimed at the panel 20 px away starts a system upgrade.
- `modules/koompi/bar/StyledPopup.qml:73-79`: the horizontal-bar popup's left margin is the hover target's centre minus half the popup width, never clamped. The clock popup (`ClockWidgetPopup.qml`, `Super+Ctrl+4`) runs off the right edge on a 1920 px screen: the date, the uptime value and the to-do line are cut.

## Do

1. **Badge.** Move `UpdateBadge` out of `rightSidebarButton` so it is its own bar item, immediately left of that button, with its own hit area. Glyph only (`system_update`), no count on the bar.
2. **Updates popup.** New `modules/koompi/bar/UpdatesPopup.qml`, a `StyledPopup` with `clickToShow: true` (a hover popup cannot hold a button). Clicking the badge opens it; clicking again or outside closes it. Content, in plain words: a header "Updates available", one line "N packages can be updated", the time of the last check if `services/Updates.qml` knows it (add a `lastChecked` property there only if needed and only the property; `Updates.qml` is yours for that one addition), and two buttons: "Update now" (runs the existing `runUpdate` command, then closes the popup) and "Check again" (`Updates.refresh()`). Middle-click on the badge keeps checking again.
3. **Clamp.** In `StyledPopup.qml`, clamp the horizontal-bar popup so its whole background stays inside the screen it opens on (respect `elevationMargin`). Do the same for the vertical bar's `top`. One clamp function, used by both.
4. **Tests.** `tests/test_bar_keys.sh` already captures the bar headlessly with `KOOMPI_UPDATES_FORCE=12` and opens the clock popup by IPC. Extend it, or add a sibling test, so it fails when (a) the badge sits inside the right-sidebar button again, and (b) the clock popup's background extends past the screen edge in a narrow (e.g. 1280 px) virtual screen. Measure geometry from the probe, not by grepping QML.
5. **Docs.** `docs/navigation.md` Entry points table, "Update badge" row: the new behaviour.

## Acceptance

- Headless screenshots (`shellshot.sh` with `KOOMPI_UPDATES_FORCE=12` in the env): the bar with the badge beside the panel button, the updates popup open, and the clock popup fully on screen at 1280x400 and 1920x1200.
- The new assertions fail on `dev` and pass on your branch; paste both.
- Full suite: no new failures against the baseline.

## Out of scope

- Reordering the rest of the bar, mode indicators, the panel itself (Phase 2).
- Download size or restart-needed detection (needs a new probe; note it in the report if you see a cheap source).

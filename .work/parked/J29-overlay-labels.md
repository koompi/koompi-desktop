# J29: the widget overlay says what its buttons are

Audit: `docs/design/ux-audit-2026-10-07.md` section 3.11 (Widget overlay). Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.
Files owned:
- `modules/koompi/overlay/OverlayContext.qml` and `OverlayTaskbar.qml`;
- one property in `modules/common/Persistent.qml` under `overlay` (`:93-154`);
- a new `tests/test_overlay_labels.sh`;
- the overlay lines of `docs/manual/*`.
Depends on: nothing in flight (the overlay is not a J07 surface).
Shared with:
- `Persistent.qml` is common; add only the one property, inside the `overlay` block.
- J31 (glyph tuning) sets the shell-wide on/off rule; follow it here: toggled means a filled glyph and the accent plate, not colour alone.

## Evidence (on `dev`)

- `Super+G` opens a row of nine unlabelled glyphs: seven widget buttons from `OverlayContext.availableWidgets` (`OverlayContext.qml:10-18`), then the time and battery.
- The list carries `identifier` and `materialSymbol` only, with no name.
- `OverlayTaskbar.qml:114-150` (`WidgetButton`): glyph only, no tooltip; right-click (`altAction`) centres the widget, which nothing tells you. The toggled state is `colBackgroundToggled` plus a colour change (`:147`), so on and off differ by colour alone.

## Do

1. Each widget gets a translated name in `availableWidgets`: Crosshair, Frame-rate limit, Floating image, Screen recorder, System resources, Notes, Volume mixer. Check the names against what each widget actually does before using these.
2. Every button has a tooltip: "<name>", and on a second line, "Right-click to centre it". Use the shell's `StyledToolTip`.
3. **First use.** The first three times the overlay opens, each button shows its name under the glyph; after that, glyphs only. Count in `Persistent.states.overlay.labelsSeen`. A long-press or hover still shows the tooltip.
4. Toggled buttons show the filled glyph (`fill: 1`) on the accent plate, so state does not ride on colour alone.

## Tests (fail on `dev` first)

- A headless probe opens the overlay with a fresh state dir: seven buttons each have a non-empty name and a tooltip, and labels are visible.
- After three opens the labels are hidden and tooltips remain.
- A toggled button's glyph `fill` is 1.

## Acceptance

- shellshot renders at 1920x1200 and 1366x768, dark and light: first open (labels) and a later open (tooltip on hover). Look at them in full.
- Test before/after output. Full suite: 0 failed (J15's flake aside).

## Out of scope

- What the widgets do. The time and battery items.

# J06: external monitors at their best refresh

Audit: `docs/design/ux-audit-2026-10-07.md` section 5, F8. Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.

## Evidence

- `dots/.config/hypr/hyprland/general.lua:2-7`: one catch-all `hl.monitor` with `mode = "preferred"`. The live HDMI monitor runs 1920x1080@60 while it offers 74.97 Hz (`hyprctl monitors`, read by the lead).

## Do

Make the catch-all rule pick the highest refresh rate at the preferred resolution (Hyprland's `highrr`, or the Lua provider's equivalent: confirm what the `hl.monitor` mode accepts by reading Hyprland's Lua config docs or source on this machine, not from memory). Check whether Settings > Displays writes its own per-monitor rules (`tests/test_displays_persist.sh`, `modules/settings/` Displays page) and that a saved per-monitor rule still wins over the catch-all. Add or extend a test that fails if the catch-all goes back to `preferred`, and explain in the commit why `highrr` is safe for the internal panel (it resolves to the same 60 Hz there).

## Acceptance

- The refresh test before/after output.
- Full suite: 0 failed.

## Out of scope

- Applying anything to the live session. Do not run `hyprctl` against the running compositor; the lead verifies the live effect only with the founder's authorisation.

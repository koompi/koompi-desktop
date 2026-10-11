# J33: one icon plate for every app icon, built plate-first, then masked

Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.
The identity is decided; this job builds it. Read `/home/userx/workspace/koompi/koompi-desktop/.work/mockups/README.md` (J14) in full first: it holds the geometry, the base-theme findings and the coverage tables.

## Decided

`J14_icon_identity C_built_B_first p=0.77 (jev-1.13.0)`: squircle-masked colour icons as the end state, built in two stages, each measured. The founder delegated the pick.

## Stage 1: the plate (B)

- One plate component that every app icon in the shell goes through. Find every place the shell draws an app icon first (Launchpad, Search results, dock, overview, waffle taskbar and start menu, and the bar if it shows app icons) and list them in the report.
- The plate, from J14:
  - a rounded square with a corner radius of 28 % of its side, following the exponent-2.5 `rounding_power` curve (`dots/.config/hypr/hyprland/general.lua:104`);
  - its fill is the highest surface layer in dark mode and white in light mode, with a 1 px edge and an elevation-1 shadow;
  - the icon's body fills 72 % of the plate.
- Sizes, from J14: 96 px in the Launchpad and 32 px in the bar. The switcher size (64 px) applies when J17 lands.
- The shadow is rendered once and reused, not a shader pass per plate per frame. Prove that with a measurement.
- Any icon works: a theme icon, a hicolor vendor icon, a pixmap. One that resolves to nothing gets one rule (a category glyph or a letter on the plate), and the report says which and why.

## Stage 2: the mask (C)

- For icons whose theme declares a full-bleed body, mask the icon to the squircle so its body fills the plate.
  - Per-theme metadata gives the body box; for WhiteSur it is 6.25 % to 93.75 % of the canvas, shared by 23 of the 24 default apps.
  - Every other icon keeps the stage-1 plate.
- The masked result is rendered once per icon and cached, not per frame. Prove it.
- Stage 2 needs a full-bleed base theme. WhiteSur-green is one; the shipped breeze-plus-dark is not.
  - Find how KOOMPI ships icon themes and whether WhiteSur-green can be shipped (package, license, size).
  - If shipping it is not settled, stop after stage 1 and report the options. Do not pick a theme yourself.
- Overhangs (Text Editor's pen, Photos' lens, the Screenshot and Updates badges, Okular's glasses) are clipped by design. Show them in a render.

## Measure

Run `/home/userx/workspace/koompi/koompi-desktop/.work/tools/measure_surfaces.sh` and take a full run's `full` line on dev, after stage 1 and after stage 2. Also time the Launchpad's first open with 24 icons, cold and warm, on each.

## Tests (fail on dev first)

- Every app-icon site goes through the plate component (a static check).
- An icon with no theme metadata gets the plate unmasked.
- An icon that resolves to nothing gets the fallback.
- A masked icon is rendered once, not per frame.

## Acceptance

- Renders: Launchpad, dock and Search at 1920x1200 and 1366x768, dark and light, after each stage. Look at each and say what you see.
- Measurements before and after each stage.
- Full suite: no new failures.

## Out of scope

- Drawing KOOMPI's own icons (J34) and the cursor (J35), both deferred.
- The Alt+Tab switcher, which J17 builds on this component.

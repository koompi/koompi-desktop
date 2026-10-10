# J14: three identity mockups for the founder to choose from

Audit: `docs/design/ux-audit-2026-10-07.md` section 4 (decision D5: a KOOMPI icon theme on a wide-coverage base, and the shell draws every app icon on one squircle plate). Item 6 there: before any build, three directions rendered side by side; the founder picks from pictures. Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first; the product-code rules apply to nothing here, the rest do.

This job produces pictures, not product code. Everything you write lives in `/home/userx/workspace/koompi/koompi-desktop/.work/mockups/` (commit nothing to the product tree; the lead commits the mockups folder).

## What exists

- Shell glyphs: Material Symbols Rounded (variable: weight, fill, grade, optical size), `modules/common/Appearance.qml` fonts (Google Sans Flex for UI), the brand KOOMPI star (`assets/icons/koompi-symbolic.svg`, and the `KOOMPI Star` font).
- App icon themes on this machine: `breeze-plus-dark` (shipped today, flat, weak coverage: no Dolphin icon), `breeze-dark`, and in `~/.local/share/icons`: `WhiteSur-green` (26.7k SVGs, 3.6k symbolic), `Fluent-green` (25.2k, 3.5k symbolic), `Mkos-Big-Sur`.
- Squircle: Hyprland uses `rounding_power = 2.5` for windows; the plate reuses that curve.
- Colours: the shell's Material You palette from the wallpaper (`Appearance.m3colors`), brand green accent. Render with the default KOOMPI wallpaper (`assets/images/default_wallpaper.png` in the shell tree) as the backdrop.

## The three directions (all within D5)

- **A. Tinted glyph plates.** Each app is its *symbolic* icon from the base theme, drawn in the palette's on-container colour on a tonal squircle plate (Material You "themed icons"). Most uniform, most KOOMPI; vendor colour is lost.
- **B. Colour icon on a plate.** The base theme's full-colour icon inset to 72% on one uniform plate (light plate in light mode, raised dark plate in dark), soft 1-level shadow. Keeps recognition, adds uniformity.
- **C. Squircle-masked colour icons.** Full-colour icons drawn edge to edge and clipped by the squircle; base theme `WhiteSur-green` or `Fluent-green` (render both, pick the better one, say why). Closest to macOS.

Each direction also shows its cursor choice: A and B with Adwaita (today), C with Bibata (`/usr/share/icons/Bibata-Modern-Classic`). Draw the cursor image from the theme's files beside the bar.

## What each mockup shows (one 1920x1200 frame per direction per mode)

1. The bar's right end: status glyphs (Wi-Fi, battery with percent, input source, Control Center glyph, clock), and the left end: KOOMPI star and the focused app's icon and name.
2. A Launchpad grid: 4 rows of 6 real apps a KOOMPI user has (Files/Dolphin, Chrome, Telegram, WezTerm, Settings, Okular, LibreOffice Writer, Calc, Impress, Zed, Discord, Signal, Obsidian, KDE Connect, Calculator, Camera, Music, Photos/Loupe, Text editor, System monitor, Screenshot, Help, Updates, Wallpaper). Use the base theme's icon for each; where a theme lacks one, say which and use its fallback the way Qt would.
3. An Alt+Tab switcher row with 6 apps, one selected.
4. A Control Center module grid: Wi-Fi, Bluetooth, Do Not Disturb, Keep awake as toggles (two on, two off: on means filled glyph + accent plate + the word "On"), and brightness and volume sliders.

Dark and light mode: six frames total, plus `compare-dark.png` and `compare-light.png` placing the three side by side at half scale with a large A / B / C label.

## How to render

A standalone QML file per direction (or one with a `direction` property) under `.work/mockups/`, run through `/home/userx/workspace/koompi/koompi-desktop/.work/tools/shellshot.sh` with a `run:` step or a probe root, screenshotted by its `shot:` step. Icons are resolved to file paths by a small script you write (name to SVG path for a given theme, following each theme's `index.theme` Inherits chain), so every frame uses real theme files, not Qt's current theme. Typography and spacing follow `Appearance.qml` tokens so the frames look like the shell, not a web page.

## Acceptance

- The eight PNGs exist and you have looked at every one at full size. Each must be good enough to ship: aligned on a grid, no clipped text, no missing icons (or each one named), real fonts.
- `.work/mockups/README.md`: one paragraph per direction saying what it costs to build (which parts are shell code, which need drawn icons), and the list of icons each base theme lacks for the KOOMPI app set.

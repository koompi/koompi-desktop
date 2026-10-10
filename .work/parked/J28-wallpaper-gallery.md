# J28: picking a wallpaper is a gallery, not a file browser

Audit: `docs/design/ux-audit-2026-10-07.md` section 3.11 (Wallpaper picker). Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.
Files owned:
- `modules/koompi/wallpaperSelector/*` (`WallpaperSelector.qml` is not a J07 surface);
- `services/Wallpapers.qml`, plus a new `services/WallpaperGallery.qml` if a second service reads better;
- a new `tests/test_wallpaper_gallery.sh`;
- the wallpaper lines of `docs/manual/*`.
Depends on: nothing in flight.
Shared with: `services/DarkMode.qml` is read, never edited. Day/night switching listens to it.

## Evidence (on `dev`)

- The live picker shows a `/ home userx Pictures Wallpapers` breadcrumb and file names such as `random_wallpaper-ws4.png` under the pictures (audit, live seat).
- `WallpaperSelectorContent.qml`:
  - `:165-232`: quick-folder buttons (Home, Documents, Downloads, Pictures, Videos, Wallpapers);
  - `:243-251`: an `AddressBar` of the current directory;
  - `:280-310`: the grid over `Wallpapers.folderModel`;
  - `:350-366`: the system-file-picker fallback.
- The file is at its 453-line ratchet.
- `services/Wallpapers.qml:22`: `defaultFolder` is `~/Pictures/Wallpapers`; `:70` `select()`; `:183-207` per-workspace wallpapers.
- The KOOMPI collection installs to `/usr/share/backgrounds/koompi` (`sdata/dist-arch/koompi-branding/PKGBUILD:36-47`, from `wallpapers/*.jpg`: `koompi-antlers.jpg`, `koompi-synthwave.jpg`). The shell's default is `assets/images/default_wallpaper.png`.
- `services/DarkMode.qml:17-39`: an automatic light/dark schedule with sunrise and sunset. No wallpaper follows it today, and no day/night wallpaper pairs exist in the tree.

## Do

1. **Sections, no paths.**
   - "KOOMPI": `/usr/share/backgrounds/koompi` and the shell default.
   - "Your photos": `~/Pictures/Wallpapers`, then `~/Pictures`, newest first.
   - "Day and night": pairs, see 3.
   Each section is a row or grid of thumbnails with the applied one marked. No breadcrumb, no folder buttons, no file names. KOOMPI wallpapers may show a short title from a small manifest beside them; photos show none.
2. **Other files.** One "Choose a file…" button keeps the system picker (`:350-366`) for anything else. Drag-and-drop and paste of an image still apply it (`handleFilePasting`).
3. **Day and night.**
   - A pair is two images named `<name>-day.<ext>` and `<name>-night.<ext>` in the KOOMPI folder or `~/Pictures/Wallpapers`.
   - Choosing a pair applies the one matching `DarkMode.dark` and switches when it changes, including at the automatic sunrise and sunset.
   - With no pair present the section is hidden, and the report names the art needed. Do not invent art.
4. Per-workspace wallpapers (`Wallpapers.forWorkspace`) keep working. Choosing from the gallery behaves as choosing from the grid does today.
5. Keyboard: arrows move between thumbnails across sections, Enter applies, Esc closes.

## Tests (fail on `dev` first)

- A headless probe with a fixture HOME (`Pictures/Wallpapers` with two images and one `x-day.png`/`x-night.png` pair) and a fixture KOOMPI dir:
  - no visible text contains `/` or a file extension;
  - the three sections exist;
  - applying the pair with `DarkMode` dark selects the night image, and flipping it selects the day image.
- `Wallpapers.select` is shimmed to record calls; nothing runs the real `switchwall.sh` against the user's config.

## Acceptance

- shellshot renders at 1920x1200 and 1366x768, dark and light, looked at in full.
- Test before/after output. Full suite: 0 failed (J15's flake aside).

## Out of scope

- Producing new wallpaper art. Video wallpapers. The colour-generation pipeline.

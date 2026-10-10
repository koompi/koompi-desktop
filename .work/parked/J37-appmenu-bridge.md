# J37: global menus for Qt apps on Wayland, so the xcb allowlist can go

Audit: `docs/design/ux-audit-2026-10-07.md` sections 5 (F4) and 7 (D1: the founder chose "staged, allowlist now and bridge later"; this is the "later"). Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.
Files owned:
- a new Hyprland plugin under `plugins/` (if stage A picks that route) and its `sdata/dist-arch/` package;
- `globalmenu/core/src/compositor.rs` and the registrar's window keying (`globalmenu/core/src/registrar.rs`);
- `globalmenu/daemon/src/main.rs` only where the keying changes;
- in stage B, the allowlist in `dots/.local/bin/koompi-launch` that J09 added, and J09's tests;
- `docs/navigation.md` Global menu row (`:303`).
Depends on: J09 merged (the allowlist exists) and J13 merged (also edits `koompi-launch`).

## Evidence (on `dev`)

- `globalmenu/` is the Rust global-menu daemon:
  - the registrar keys every menu by an X11 window id (`core/src/registrar.rs:17` `window_id: u32`, `:58` `for_window`);
  - `core/src/x11.rs:1-3` reads XWayland properties for GTK menus;
  - `core/src/compositor.rs:1-26` asks the compositor for the focused window and whether it is `xwayland`.
- `tests/test_globalmenu.sh` runs a conformance suite against both daemons.
- A Qt app on Wayland has no X11 window id. With KDE's platform integration it announces its menu through the `org_kde_kwin_appmenu` Wayland protocol, which the compositor must implement. Hyprland does not. That is why menu apps stay on xcb (J09's allowlist).
- The repo already ships a Hyprland plugin: `plugins/koompi-swipe-progress/` (`main.cpp`, `Makefile`, rebuilt on Hyprland upgrades by `sdata/dist-arch/koompi-swipe-progress/` and its pacman hook).

## Stage A: prove a route, then stop

In the nested-Hyprland harness (a repo test in the shape of `tests/test_search_window_focus.sh`, private bus), with `okular` or `dolphin` under `QT_QPA_PLATFORM=wayland`:

1. Confirm what the app does without the protocol: whether it exports `com.canonical.dbusmenu` anyway, and on which object path. Use `busctl --user` on the private bus.
2. Prototype the smallest route that gives the daemon "this Wayland window → (service, menu path)". The likely one is a plugin implementing `org_kde_kwin_appmenu_manager`, exposing the mapping by window address (event socket or a `hyprctl` plugin command). Name any alternative you find and why it is worse.
3. Write `docs/design/appmenu-bridge.md` (one sentence per line): the route, its maintenance cost across Hyprland upgrades (the swipe-progress plugin's rebuild hook is the precedent), the failure mode when the plugin is missing (menus fall back to xcb apps only, never a crash), and the evidence. Stop for the lead's decision (Jev).

## Stage B: build (after the lead's go)

1. The plugin or route, packaged like swipe-progress.
2. The registrar keys menus by window address as well as X11 id; the compositor trait reports Wayland windows.
3. Retire the allowlist: Qt apps run on Wayland. Without the plugin (unsupported Hyprland, failed rebuild), fall back to the allowlist automatically, so a user never loses menus.
4. Docs: navigation row and `docs/agents/`.

## Tests

- The conformance suite (`tests/test_globalmenu.sh`) gains a Wayland-window case. A nested test opens a Qt app on Wayland and reads its top-level menus from the daemon's output.
- The fallback: the plugin absent means the allowlist path, still with menus.

## Acceptance

- Stage A note and its test output. Stage B: dolphin, okular, konsole and ark show their menus in the bar on Wayland in the nested harness. Measured launch times there, before and after.
- Full suite: 0 failed.

## Out of scope

- GTK apps (already handled by `x11.rs`/`gtkmenu.rs`). KDE's own shell. Menus for Electron apps.

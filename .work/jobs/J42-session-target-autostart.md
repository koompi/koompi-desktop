# J42: the session target ships with KOOMPI, and login items start

Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.
Files owned:
- `dots/.config/systemd/user/hyprland-session.target` (new)
- `dots/.config/hypr/hyprland/execs.lua:31-33` (the target line and its comment)
- `dots/.config/autostart/` (new)
- `sdata/install/files.sh` (only `KEEP_PATHS`, if the overrides go there)
- the false comments in `sdata/dist-arch/koompi-toolkit/PKGBUILD:18-21`, `sdata/dist-debian/packages.list:94` and `sdata/dist-fedora/packages.list:109`
- `tests/test_hypridle_logged.sh`, only if the target line's shape changes
- one new test
- the doc that describes session start-up

## Evidence (lead, 2026-10-07, read only on the live seat)

- `execs.lua:33` runs `dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE && systemctl --user start hyprland-session.target && systemctl --user start xdg-desktop-autostart.target`.
- `/usr/lib/systemd/user/xdg-desktop-autostart.target` has `RefuseManualStart=yes` and `StopWhenUnneeded=yes`, so the last start is refused on every machine.
  - This boot it has no `ActiveEnterTimestamp`.
  - fcitx5 is not running.
  - The founder's own login items in `~/.config/autostart` (fcitx5, a Chrome app) never start.
  - systemd.special(7): a session opts in with `Wants=xdg-desktop-autostart.target`.
- `hyprland-session.target` exists only at `~/.config/systemd/user/hyprland-session.target` on the founder's host. No package owns it, it was hand-made on 2026-06-17, and `git log --all -- '*hyprland-session.target'` is empty.
  - Its content: `[Unit] Description=Hyprland compositor session / BindsTo=graphical-session.target / Wants=graphical-session-pre.target / After=graphical-session-pre.target`.
  - On a fresh install the start fails and `graphical-session.target` never activates. hypridle, koompi-crash-watch, touch-gestures, koompi-migrate-notify and the portals (`execs.lua:31`) never start.
- The generated units, and what their conditions do under `XDG_CURRENT_DESKTOP=KOOMPI:Hyprland`:
  - Would run:
    - the founder's Chrome app and `fcitx5` (`~/.config/autostart`)
    - `org.fcitx.Fcitx5` (system)
    - `nm-applet` (`NotShowIn=KDE;GNOME`)
    - `geoclue-demo-agent` (`NotShowIn=GNOME`)
  - Filtered out: gnome-keyring pkcs11 and secrets (`OnlyShowIn=Unity:MATE:Cinnamon`) and the Plasma session restore (`OnlyShowIn=KDE`).

## Decided

`J42_autostart_scope autostart_hide_duplicates p=0.98 (jev-1.13.0)`.
The session opts into XDG autostart, and two system entries are hidden:
- `nm-applet`: the shell has its own network panel.
- `geoclue-demo-agent`: commit `b63a85283` moved it to start on demand from Weather, which is off by default.

## Do

1. Ship `hyprland-session.target` in `dots/.config/systemd/user/`: the host's content plus `Wants=xdg-desktop-autostart.target`.
   The installer merges `.config` (copy in, never delete; `sdata/install/files.sh:1-11`), so confirm a fresh install gets it, and say what makes the user manager see it on first login.
2. In `execs.lua:33`, drop `&& systemctl --user start xdg-desktop-autostart.target`.
   Keep the rest of the line, which `tests/test_hypridle_logged.sh:35-38` asserts. Update the comment above it to one short line.
3. Hide the two entries with user-directory overrides of the same filename (`nm-applet.desktop`, `geoclue-demo-agent.desktop`, `Hidden=true`).
   A user who wants one back edits that file, so their edit must survive an update. Decide between `KEEP_PATHS` and another mechanism, and say which and why.
4. Correct the three comments that say the session already starts `xdg-desktop-autostart.target`.
5. Add a test that fails on `dev` and passes after.
   - `systemd-analyze --user verify` on the shipped unit, or the closest offline equivalent.
   - The target `Wants=xdg-desktop-autostart.target` and `BindsTo=graphical-session.target`.
   - Nothing in the tree starts `xdg-desktop-autostart.target` by hand.
   - Run `/usr/lib/systemd/user-generators/systemd-xdg-autostart-generator` into a temp output dir, with a temp `XDG_CONFIG_HOME` holding the repo's `dots/.config/autostart`. No unit for `nm-applet` or `geoclue-demo-agent`, and a unit for `org.fcitx.Fcitx5`.
   - Skip loudly if the generator is missing.
6. Add one paragraph where the docs describe session start-up (find it): apps set to start at login now do, and the two that KOOMPI hides, with why.

## Never

- Do not touch the founder's user manager: no `systemctl --user start/stop/enable/daemon-reload/import-environment`, and no writes under the real `~/.config`.
- Generator runs and verifies use temp dirs.
- The deploy to the founder's seat is the lead's, after the founder's word. That deploy replaces the hand-made unit, and the founder's Chrome app and fcitx5 start at login for the first time.

## Acceptance

- The test's output on `dev` (failing) and after (passing).
- The generator listing before and after, from the temp dirs.
- Full suite through `heavy.sh`: no new failures.

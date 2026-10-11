# J42: the session target ships with KOOMPI, and login items start

Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.
Files owned:
- `dots/.config/systemd/user/hyprland-session.target` (new)
- `dots/.config/hypr/hyprland/execs.lua:31-33` (the target line and its comment)
- `dots/.config/autostart/` (new)
- `sdata/install/files.sh` (only `KEEP_PATHS`, if the overrides go there)
- the false comment in `sdata/dist-arch/koompi-toolkit/PKGBUILD:20-21`, and the KDE Connect comment in `sdata/dist-arch/koompi-apps/PKGBUILD:97-99`
- `sdata/migrations/<ts>-session-target-autostart.sh` (new)
- `tests/test_hypridle_logged.sh`, only if the target line's shape changes
- one new test (the migration's checks may live in it)
- `docs/agents/hyprland.md` (a new section on session start-up)

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

## Round 1 (worker, 2026-10-07): stopped at contract step 4, nothing committed

The permission check refused `git checkout -B <branch> dev`, and the worktree was auto-cleaned when the agent ended.
Its findings stand, and its scratch files are in `/home/userx/.tmp/j42-gen.zXSQtv` (candidate target and overrides, generator helpers).
- The candidate target is the host's content plus `Wants=xdg-desktop-autostart.target`, with one comment line.
  `systemd-analyze --user verify` exits 0 on it, but also exits 0 on a `Wantz=` typo and only prints a warning, so the test fails on any verify output.
- Generator before, system entries only: fcitx5, kdeconnect, nm-applet and geoclue run; gnome-keyring pkcs11, secrets and the Plasma restore are filtered.
  After the overrides, nm-applet and geoclue are gone, and flipping one override to `Hidden=false` brings its unit back.
- Test design, accepted: static asserts on the target, a repo-wide grep that nothing starts the target by hand, a check that every file in `dots/.config/autostart` is in `KEEP_PATHS`, and the generator against a fixture `XDG_CONFIG_DIRS`.
  The fixture has three entries with `Exec=/usr/bin/true`, and a control run without overrides must produce all three units.
  That replaces the spec's "a unit for `org.fcitx.Fcitx5`" check, which fails on a host without fcitx5.
- Overrides go in `KEEP_PATHS` (`sdata/install/files.sh:4-8,198,285-290`): written only when absent, so a user's edit survives.
  A deleted override comes back on the next update, so the docs say to edit it, not delete it.

## Round 2 (lead, after round 1)

1. Comments: only `sdata/dist-arch/koompi-toolkit/PKGBUILD:20-21` is false.
   The debian and fedora lines are true as written; leave them.
   `sdata/dist-arch/koompi-apps/PKGBUILD:97-99` credits a "shell's KDE Connect integration" that does not exist (the shell has no KDE Connect UI).
   Say what actually needs the daemon (Remote Input through `koompi-remotedesktop-portal`) and that it starts when KDE Connect opens.
2. `J42_kdeconnect_login hide_kdeconnect p=0.73 (jev-1.13.0)`: ship a third override, `org.kde.kdeconnect.daemon.desktop` with `Hidden=true`, in `KEEP_PATHS` like the other two.
   kdeconnectd is D-Bus activated, so opening KDE Connect starts it.
   The docs paragraph names all three and why.
3. Existing package-route users get neither file.
   `koompi-migrate` syncs only `quickshell/koompi` and `hypr/hyprland` (`dots/.local/bin/koompi-migrate:181-198`), and `/etc/skel` seeds new users only.
   Add `sdata/migrations/<ts>-session-target-autostart.sh` with `koompi-migrate new session-target-autostart`, following `docs/agents/migrations.md`.
   - The target: write it if absent, do nothing if identical, and if it differs, back it up first and then replace it, as `sync_tree` does for a `.config` file.
   - The three overrides: write each one only if absent.
   - Idempotent. The test proves a second run changes nothing, an edited override survives, and a differing target is backed up and then replaced.
4. Docs home: a short section in `docs/agents/hyprland.md` after "`custom/` vs `hyprland/`".
5. Do not add `Before=xdg-desktop-autostart.target`; the spec is the scope.

## Never

- Do not touch the founder's user manager: no `systemctl --user start/stop/enable/daemon-reload/import-environment`, and no writes under the real `~/.config`.
- Generator runs and verifies use temp dirs.
- The deploy to the founder's seat is the lead's, after the founder's word. That deploy replaces the hand-made unit, and the founder's Chrome app and fcitx5 start at login for the first time.

## Acceptance

- The test's output on `dev` (failing) and after (passing).
- The generator listing before and after, from the temp dirs.
- Full suite through `heavy.sh`: no new failures.

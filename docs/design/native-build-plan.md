# Native build: Rust for services, Zig for tools

Status: **plan**, written 2026-10-15. N1 is merged on `dev`; nothing else has started.
Goal: each native part has one language, one build and one package, and both install routes ship the same programs.
Services keep running when the shell restarts, the shell stops polling for what a service can push, and every change is measured.

## The split

The founder agreed it on 2026-10-15.
A language does not make this desktop fast: Rust and Zig both compile to native code with no garbage collector.
What it decides is how reliable a part is and how easy it is to build.
Speed comes from where work runs: in the shell, or in a service that pushes events.

| Language | For | Parts |
|---|---|---|
| **Rust** | Services that run all day, speak D-Bus, sockets or sysfs, and parse what other apps send | `koompi-shelld` and its crates in `shell-services/`, the global menu in `globalmenu/`, `koompi-agent-memd` |
| **Zig** | Short-lived tools whose start-up and size matter, and leaf programs that mostly call C | the `koompi` CLI (`cli/`), the installer TUI (`installer/`, OS ISO plan C) |
| **C++** | Hyprland plugins, because Hyprland's plugin interface is C++ | `plugins/koompi-swipe-progress` |
| **QML** | Drawing and input only | the shell |

## Baseline, live seat, 2026-10-15

Measured 50 minutes after the shell started.
"PSS" is memory with shared pages split between the processes that share them.

| Process | PSS | Idle CPU | Notes |
|---|---|---|---|
| `qs -c koompi` | **461 MB**, of which 406 MB is anonymous | about 0.25 %, ~4.5 context switches a second | 98 % of the desktop's own memory |
| `koompi-shelld` | 7 MB | ~0 | 7.4 MB binary, not stripped |
| global menu daemon | 2 MB | ~0 | 5.3 MB binary, not stripped |
| `koompi` CLI | — | — | 2.3 ms for `--help` and 3.0 ms for `paths`; 3.9 MB static binary with debug info |

From the timers, the shell forks about 61 processes a minute while idle, unlocked and on AC.
This is an estimate; N0 measures it.

## What the audit found

1. **The package route has no services.**
   - `koompi-shell` built only the Zig CLI; N1 added the menu daemon.
   - `koompi-shelld` and `koompi-agent-memd` still exist only where `./setup` built them into `~/.local/bin`.
   - `ShellServices.qml:17-25` looks only there, or in the repo's `target/`.
   - So on KOOMPI OS the bar has no window list, network, power, brightness or Bluetooth service.
   - `build-packages.yml` installs neither Cargo nor Zig, so CI cannot build `koompi-shell` either.
2. **The two routes build different things.**
   - `./setup` never builds the swipe plugin.
   - The packages never build `koompi-shelld`.
3. **Code that is built but not used.**
   - The Zig global menu (N1 deletes it).
   - `audiod`: Zig, built only by tests, started by nothing. Only the unwired `audio` crate would spawn it.
   - Five crates compiled only by tests: `audio`, `mpris`, `tray`, `notifications`, `session`.
     `shelld` depends on `service`, `hyprland`, `network`, `power`, `brightness` and `bluetooth`.
     The 2026-08-10 commit (`f7f8290df`) left the others waiting for "a toolkit".
   - `cli/build.zig` defines `zig build test`, and nothing runs it.
4. **Release builds are not lean.**
   - Neither Cargo workspace sets `lto`, `codegen-units` or `strip`.
   - The CLI ships with debug info, and `cli/` has no `minimum_zig_version`.
   - `shell-services/` and `globalmenu/` are separate workspaces, with two lockfiles and two target directories.
5. **Stopping a process does not work by name.**
   - `stop_processes` (`sdata/lib/common.sh`) and `keybinds.lua:106` look for `global-menu-daemon`.
   - The kernel cuts process names to 15 characters (`koompi-global-m`), so `pgrep -x` and `killall` never match.
   - Daemons die only because their stdin closes.
6. **Every service dies with the shell.**
   - `koompi-shelld`, the global menu and `koompi-agent-memd` are children of `qs` and exit on stdin EOF.
   - Each update restarts the shell, so it drops every app's menu registration (Telegram's menu was lost this way on 2026-10-15) and re-subscribes every service.
7. **The shell polls.** 30 repeating timers. The forking ones:

   | Interval | Where | What it forks |
   |---|---|---|
   | 2 s | `ModeIndicators.qml:48` | `bash`, to read the kiri pidfile |
   | 2 s | `ScreenRecording.qml:28` | `pidof wf-recorder` |
   | 3 s | `MprisController.qml:174` | `playerctl position` |
   | 60 s | `StartupApps.qml:19` | `koompi-startup-apps scan`, even while locked |
   | 60 ms | `SnapPreview.qml:144` | `hyprctl cursorpos`, during a drag |

## Decisions needed

- **D1, audio.** (a) Delete `audiod` and the `audio` crate, and keep Quickshell's in-process PipeWire, which works today and costs no process. (b) Wire `audiod` and the `audio` crate into `shelld`: a crash in libpipewire then cannot take the shell down, at the cost of one process and a protocol hop.
  **Recommendation: (a), unless a crash is traced to the shell's PipeWire code.**
  The 47 shell crashes on record are mostly test probes, and none kept a stack, so nothing is traced either way yet.
- **D2, where the menu registrar lives.** (a) A crate inside `shelld`. (b) A separate user service.
  **Recommendation: (a).** It is one process fewer and shares one D-Bus connection. `koompi-globalmenu-core` is already a library crate.
- **D3, the unwired crates.** Is a non-Quickshell toolkit still planned (`docs/design/smithay-study.md`)?
  - If not: wire `mpris`, which ends the `playerctl` fork; wire `session` if N6 needs it; delete the rest.
  - If it is: keep them, but gate them out of the default test build.

## Phases

Each job has one worker in its own worktree, and the lead verifies (AGENTS.md). Heavy runs go through `.work/tools/heavy.sh`.

### Phase 0: measure (about 1 day)

- [ ] **N0 bench.** Add `tests/bench/session.sh`, which reports:
  - PSS per session process;
  - processes forked by `qs` in a 60 s idle window (nested harness, `strace -f -e trace=execve`);
  - shell start to first frame;
  - time from a focus change to the bar's update;
  - CLI latency.

  It also runs read-only against the live seat.
  Results go to `.work/data/`.

  **Done when** two runs on the same tree agree within 10 %, and today's numbers are recorded as the baseline.

### Phase 1: one of everything (2–3 days)

- [x] **N1 global menu on Rust only.** Merged 2026-10-15 (`706d33179`..`c6e1e101b`).
  - The Zig daemon is deleted, the conformance suite lives in `globalmenu/tests/`, and the stop names match.
  - `koompi-shell` ships the daemon in `/usr/lib/koompi/`.
  - A migration removes the leftover build from existing homes.
  - Root cause: since Qt 6.10, Qt calls RegisterWindow only on xcb. On Wayland it exports `/MenuBar/<n>` and announces it through a KDE protocol Hyprland lacks.
    The daemon now finds that menubar by the focused window's pid, so Wayland Qt apps have menus and the xcb pin for Dolphin, Okular, Konsole and Ark is gone.
  - Verified: lead suite 199 passed, 2 skipped, 1 failed (`test_startup_apps.sh`, failing before). With the probe switched off, the conformance suite fails 8 checks.
  - Known limits, follow-ups:
    - One adopted menubar serves every window of a process, so a menu action in a second window of the same process (Konsole) acts on the first.
    - A Flatpak app reaches the bus through a proxy with another pid, so its Qt menu is not found.
- [ ] **N2 one build per toolchain.**
  - One Cargo workspace at `native/` or the repo root, with `shell-services/*` and `globalmenu/*` as members, one lockfile and one target directory.
  - `rust-toolchain.toml` pins the toolchain.
  - The release profile sets `lto = "thin"`, `codegen-units = 1` and `strip = true`, and keeps `overflow-checks`.
  - Zig: `cli/build.zig.zon` gets `minimum_zig_version`; release builds are stripped; `zig build test` runs in the suite.

  **Done when** `./setup` makes one `cargo build` call and one `zig build` per tool, binary sizes are recorded before and after, and the suite passes.
- [ ] **N3 package parity.**
  - A `koompi-services` package (or `koompi-shell`) builds `koompi-shelld` and the menu daemon with Cargo into `/usr/lib/koompi/` or `/usr/bin`.
  - One resolver in QML tries the setup route, then the package route, then `KOOMPI_SHELLD`.
  - `./setup` builds the swipe plugin, or the docs say it ships only as a package.

  **Done when** `makepkg` in a clean chroot builds every native binary, and a package-route session in the nested harness has `shelld` and the menu running.
- [ ] **N4 delete dead code**, per D1 and D3.
  - `audiod` and its tests under (a).
  - The unwired crates under D3.
  - `shapes/example.qml`.

  **Done when** nothing deleted is referenced, and suite time is recorded before and after.

### Phase 2: services that outlive the shell (3–5 days)

- [ ] **N5 shelld as a user service.**
  - A `koompi-shelld.service` unit, part of `graphical-session.target`.
  - It speaks the same NDJSON over a Unix socket in `$XDG_RUNTIME_DIR` instead of stdio.
  - `qs` becomes a client that reconnects.
  - The menu registrar moves in as a crate (D2).
  - `stop_processes`, `koompi-reload`, `libexec/update` and `keybinds.lua` stop restarting services with the shell.

  **Done when**, in the nested harness, `qs` restarts while `shelld` keeps its pid and an app keeps its menu.
  A crash in `qs` must also leave `shelld` running, and a crash in `shelld` must be restarted by systemd without the shell noticing more than a reconnect.

### Phase 3: push, don't poll (3–4 days)

- [ ] **N6 events instead of timers.**
  - `shelld` watches the kiri and `wf-recorder` processes (pidfd or inotify on the pidfile) and pushes their state.
  - `StartupApps` follows the autostart directories through inotify.
  - MPRIS position comes from the `mpris` crate: `Seeked` plus interpolation in QML.
  - `SnapPreview` gets the cursor from the plugin, or forks only while a drag is live (measure that first).
  - Timers that only animate become `Animation`s.

  **Done when** N0 shows at most 2 forks a minute from an idle, unlocked shell (from about 61), and no indicator is more than 250 ms late.

### Phase 4: shell memory (2–3 days to find; the jobs follow)

- [ ] **N7 profile the 406 MB.**
  - PSS per surface (`.work/tools/measure_surfaces.sh`).
  - Image caches: wallpapers, thumbnails, icon plates.
  - The JS heap per singleton.

  This is QML work, not Rust or Zig, but it is the biggest lever on the desktop's footprint.

  **Done when** a breakdown is written and the three largest consumers each have a job with a target.

### Zig track (alongside, small)

- **The CLI** gets N2's floor, strip and test.
  Its latency is mostly the bash helpers it hands off to, at 3 ms against 2 ms for the binary. That is fine; do not rewrite them for speed.
- **The installer** follows `docs/design/koompi-os-iso-plan.md` (installer C after A). It is not part of this plan.

## Order and risks

- **Order:** N0, then N1 to N4, then N5, N6 and N7. N5 depends on N2 and N3, because the unit has to start the packaged binary as well. N6 depends on N5, because the events come from `shelld`.
- **Risk:** N5 changes every reload and update path. `test_update_*`, `test_hyprland_service` and `test_lock_survives_restart` are the guards. Deploy only with the founder's word, and never while the screen is locked (the shell restart kills the lock screen).
- **Risk:** N3's package route needs a clean chroot; the signed `[koompi]` repo (ISO plan phase 1) is not required for a local `makepkg` check.

# J48 report

Branch tip 02437f172, base 4c0e2db9a, 12 commits. The main checkout's .work/ refused the write, so this file is only in the handoff dir.

## Machine-specific values
- general.lua touchscreen output: already read from /sys/class/drm; fine.
- ai.sh write_litert_lm_config: hard-coded backend gpu and 8 threads (the founder's Arc laptop). Now cpu_thread_count comes from nproc and the backend is gpu only when /dev/dri/renderD* exists. tests/test_litert_config_portable.sh fails on the old code (cpu_thread_count is 8 on a 2-core machine).
- system.sh btintel_pcie suspend hook: Intel-laptop only, but it exits 0 unless the module is loaded; left as is (gating would break test_suspend_hook).
- agent_memory.sh MEMD_REPO_URL github.com/rithythul/...: a real upstream repo; left.
- kb_layout us,kh: the market default; left.
- Remaining hits (eDP-1, /home/userx, uid 1000) are Rust test fixtures and doc comments.

## Doc mismatches
- 10-updates-and-going-back.md: the bar badge is an icon with a popup (count inside, Update now button), not a count; fixed.
- setup usage named docs/dependencies.md (does not exist); now sdata/deps-info.md.
- Every command and flag in the chapter exists (`--firmware` is missing from the cli usage string but libexec/update takes it).
- Rollback exists end to end only on btrfs/OS installs (snapper). Git installs had none; the chapter now documents checkout + ./setup update, the dots backup folder and config.json.bak. One-time fixes are not reversed.
- 09-the-assistant.md and docs/agents/install.md say Kiri is github.com/koompiai/kiri packaged as koompi-kiri.
- docs/agents/install.md written (paths, units, packages, migrations).

## Container install (rootless podman, archlinux image, user with sudo, tree copied in, no mounts)
First failure: paru-bin installs but links libalpm.so.15 while pacman has .16. Fixed in the repo, in order:
1. paru-bin broken: build paru from source, removing paru-bin first (arch.sh).
2. koompi-quickshell-git pin 7511545 does not compile under gcc 16 / qt 6.11; v0.3.1 also fails (reproduced), v0.3.2 compiles. Pin moved to v0.3.2 (4f508be). I did not run the shell against 0.3.2; the host runs 0.3.1. Decision for the founder.
3. koompi-apps depends on koompi-kiri, which paru cannot find; install-apps.sh now builds it first (test_arch_local_dep_order extended; fails without it). Confirmed in the container: the build cloned github.com/koompiai/kiri, koompi-kiri 0.1.0.r67.gb380f50-1, `kiri --help` prints "Kiri - voice-to-text assistant".
4. files.sh probed shapes/qmldir, which never existed, so submodule update ran on every install and died outside a git checkout; now probes material-shapes.js (tests/test_install_submodule_check.sh, fails on old code).
5. gi (python-gobject) and cv2 (python-opencv) were never installed on Arch (used by thumbgen, the remotedesktop portal, switchwall); added to koompi-python (tests/test_arch_python_deps.sh, fails without).
Container-side, not repo fixes: mirror/GitHub timeouts (retry), PID 1 zombies hit the pids limit (use --init), no systemd (units skipped with a warning), no udev reload, no docker/podman for SearXNG.
Final run (run17): EXIT 0, only container warnings.
Not done: a from-zero run on the final tree and a clean second-run idempotence run. The container was resumed many times (each re-run skipped finished work), and a disk-full during one container commit lost a container and forced a resume from an earlier image. Logs: run1.log (first failure), run17.log (final).

## Suites
- Host: 136 passed, 4 skipped (bar_keys, globalmenu, hypridle_logged, search_bench_parity), 1 failed: test_shell_services.sh (audiod "hung" under load while the container suite ran); it passes alone. An earlier host run on the tree: 135 passed, 4 skipped, 0 failed.
- Container (cap SYS_NICE, XDG_RUNTIME_DIR set, tree made a git repo): 108 passed, 16 skipped, 17 failed. Reasons:
  - qs probes with no display (ai_model_picker, ai_threads, lock_pam, notification_exec_hint, search_commands, services_qml_bugs, cheatsheet_dispatch): no Qt platform in the container.
  - nested Hyprland (qt_platform_nested, screen_corners, search_window_focus, update_now_runs, hypr_modes): CBackend::create failed, no GPU/seat.
  - no systemd: portal_backends, suspend_hook.
  - no /etc/localtime: solar_times.
  - file_length: my git init committed the submodule's files, which the real repo does not track.
  - session_autostart: fcitx5 installed in the container adds an autostart entry.
  - skips come from missing tools (bun, docker, ...).
- A real machine with systemd and a GPU would run all of these; a systemd-nspawn boot or a QEMU VM with installer/ would prove the units and the login session.

## Removed
Containers koompi-j48-install, koompi-j48-install2 (lost in a failed commit), koompi-j48-install3; images localhost/koompi-j48-base, localhost/koompi-j48-wip. The pre-existing docker.io/library/archlinux was left.

## Round 2
- Reverted the two pin commits, then retired koompi-quickshell-git (commit "arch: depend on Arch's quickshell ..."). koompi-widgets now depends on `quickshell` plus the Qt/KDE block the old PKGBUILD carried; it was the closest existing meta (shell runtime tools), no new package. It conflicts with and replaces koompi-quickshell-git. koompi-shell and koompi-hyprland-config depend on `quickshell`; koompi-desktop-hyprland and ARCH_DEP_PKGBUILDS drop the old entry. The private-ABI version lock and its pacman hook went with the deleted PKGBUILD (nothing else used them). README row, sdata/deps-info.md, install.md and the tests.yml comment updated. tests/test_arch_quickshell_source.sh added.
- Migration: install-deps.sh removes an installed koompi-quickshell-git (-Rdd) before the survey; packaged machines get it through replaces. Proved in the container with a stand-in package (provides/conflicts quickshell; the real old one cannot be built under gcc 16): `./setup install -y --only-deps` printed "removing 1 superseded package(s): koompi-quickshell-git", rebuilt koompi-widgets, and left quickshell 0.3.2 installed. The replaces path on a signed repo was not exercised.
- Fresh from-zero install (stock archlinux image, --init, new user, final tree): r2-fresh-install.log, EXIT 0 on the first run. Second ./setup install on top: r2-second-install.log, EXIT 0, "14 metapackages already installed", "1228 already matched and needed no copy". Only container warnings (no systemd, no udev, no docker/podman).
- Note: Arch [extra] quickshell is 0.3.2 today, not 0.3.1; the shell was not run on it by me.
- Host full suite via heavy.sh: 138 passed, 4 skipped, 0 failed (r2-host-suite.log).
- Removed container koompi-j48-r2. Images: none created this round (stock archlinux left).

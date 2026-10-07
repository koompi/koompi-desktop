# J41: the crash toast reports this session's crashes, not a nested test's

Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.
Files owned: `dots/.local/bin/koompi-crash-watch`, `tests/test_crash_watch.sh`, `docs/agents/crash.md` (the filter's line).
Depends on: nothing.

## Evidence (lead, 2026-10-07, `dev` at `0009c9de8`)

- The founder asked twice why "Process crashed" toasts keep appearing. Neither batch was a crash of anything in the founder's session:
  - 21:21-21:36: xdg-desktop-portal-hyprland segfaulted 12 times, auto-started on test buses (fixed at the source in `e6d563717`).
  - 22:55-22:59: dolphin once and `hyprland-update-screen --new-version 0.56.2` twice, inside J09's nested-Hyprland test sessions.
- Every one had `COREDUMP_UID=1000`, so the live watcher announced it (`koompi-crash-watch:126` matches the uid in the journal, `:152` checks it again).
- What tells them apart is `COREDUMP_ENVIRON`. Read it with `journalctl --all -o json MESSAGE_ID=fc2e22bc6ee647b6b90729ab34a250b1 COREDUMP_PID=<pid>` for pids 827835, 843074 and 853583: `XDG_RUNTIME_DIR=/tmp/hr.vJYupN`, `/tmp/hr.hOYJWm` and `/tmp/hr.O51tId`. The founder's session runs with `/run/user/1000`, and so does every app it starts.

## Do

1. A crash whose `COREDUMP_ENVIRON` names an `XDG_RUNTIME_DIR` other than the watcher's own is not announced. The watcher writes one line to stderr (the journal) naming the program, the pid and the foreign runtime dir, so the skip is never silent.
2. When `COREDUMP_ENVIRON` is missing or has no `XDG_RUNTIME_DIR`, keep today's behaviour: announce.
3. Parse the environ inside the existing single `jq` call (`:138-144`); do not add a process per entry.
4. One line in `docs/agents/crash.md` says what is filtered and why.

## Tests (fail on `dev` first)

In `tests/test_crash_watch.sh`, with its existing fixture-fed journal:
- an entry whose environ has `XDG_RUNTIME_DIR=/tmp/hr.test` sends no toast and logs the skip;
- the same entry with the watcher's own runtime dir sends one;
- an entry without `COREDUMP_ENVIRON` sends one.

## Acceptance

- Test before/after output. Full suite: 0 failed (J15's flake aside).
- Deploying to the live seat is the lead's, with the founder's word; until then the live watcher keeps toasting nested-test crashes.

## Out of scope

- Stopping the crashes themselves (the lead fixed the update-screen trigger in the nested harnesses). The toast's wording (J03).

## Second item (lead, 2026-10-08, from J12): test shells stay off the session's polkit agent

- Every shell a test starts loads `services/PolkitService.qml:43`, whose `PolkitAgent` registers with polkitd on the system bus. A private session bus does not cover the system bus.
- In J12's runs the registration failed only because the live shell already holds it. A test shell that starts while the live shell is down or restarting can take the founder's authentication prompts and show them in a headless session nobody sees.
- Do: keep test shells from registering. Find the mechanism and say why it is the right one. For example, the harness and the shell-launching tests could point `DBUS_SYSTEM_BUS_ADDRESS` at the test's private bus, if UPower, NetworkManager and logind readers degrade without errors that fail tests. A guard in `PolkitService.qml` is another option, if it cannot misfire in the real session.
- Test, failing on `dev`: a shell started the way the tests start one makes no registration attempt on the real system bus, and `test_private_bus.sh` (or one new static check) keeps every shell-launching test and `.work/tools/{shellshot,hyprshot,measure_surfaces}.sh` on the guard.
- Files owned for this item: the shell-launching tests' launch lines, `.work/tools/{shellshot,hyprshot,measure_surfaces}.sh`, and `services/PolkitService.qml` only if the guard lives there.

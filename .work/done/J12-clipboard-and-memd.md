# J12: no process per copy; the assistant's memory starts when the assistant does

Audit: `docs/design/ux-audit-2026-10-07.md` section 5 (F9), plus a finding from the lead's measurement. Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.

## Evidence

- `dots/.config/hypr/hyprland/execs.lua:28-29`: every copy runs `bash -c 'cliphist store && qs -c $qsConfig ipc call cliphistService update'`, a bash plus a `qs` client (about 65 ms each on this machine) per copy. `services/Cliphist.qml:160-165` is the IPC it calls, and `:139-157` re-lists the whole history on each update.
- `services/MemoryService.qml:410-416`: `koompi-agent-memd` starts as soon as `Config.ready`, at login, whether or not the assistant is ever opened. In a fresh headless profile the daemon fetched a `fastembed` model (`Xenova/bge-small-en-v1.5`) into `$XDG_CACHE_HOME/userx-ai` within seconds of shell start: a download at first login nobody asked for.

## Do

1. **Clipboard.** `wl-paste --watch cliphist store` only. The shell notices new entries itself: watch cliphist's database file (resolve its path the way cliphist does: `$XDG_CACHE_HOME/cliphist/db` unless configured) with a `FileView`/`watchChanges` or equivalent, debounced (≥ 150 ms), and refresh only while a clipboard surface is open or on its next open (the list does not need to be fresh while nobody looks). Keep the IPC `update()` for anything else that calls it.
2. **memd on demand.** The daemon starts the first time something needs memory: the left sidebar or the Intelligence window opens, or an AI request is made. It stays running for the session after that. Nothing downloads a model before the user has used the assistant. Look at how the LiteRT probe was gated on `GlobalStates.sidebarLeftOpen` (vault gotcha "A periodic probe of a socket-activated backend is a permanent start") and follow the same rule.
3. Find any other `Process` with `running: ... Config.ready` that starts a long-lived daemon at login (grep `services/`), list them in the report with what each does, and gate the ones that serve a surface the user may never open. Do not change ones that serve the bar or notifications.
4. **Tests.** Clipboard: a headless test where a `cliphist store` from outside makes the shell's clipboard list grow when the clipboard view opens, with no IPC call. memd: a headless test (shadow `koompi-agent-memd` with a script that writes a marker) that the marker is absent after 10 s of idle shell and present after opening the left sidebar.

## Acceptance

- Test before/after output. Full suite: no new failures.
- In the report: the list from step 3.

## Out of scope

- The AI features themselves.

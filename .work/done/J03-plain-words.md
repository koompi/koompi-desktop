# J03: plain words for the crash toast, the empty media panel, and search's Recent rows

Audit: `docs/design/ux-audit-2026-10-07.md` sections 3.2 (S1), 3.5 (R3), 3.11 (media). Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.

## Evidence

- `dots/.local/bin/koompi-crash-watch:65-71`: summary `Process crashed: $name`, body `$signal. Click to diagnose with the local model.`, urgency critical. Live it read "Process crashed: chrome / SIGTRAP. Click to diagnose with the local …". `tests/test_crash_watch.sh:110-111` pins the old strings.
- `modules/koompi/mediaControls/MediaControls.qml:157-162`: with nothing playing it says "No active player" and "Make sure your player has MPRIS support\nor try turning off duplicate player filtering".
- `services/LauncherSearch.qml:320`: each empty-query recent app carries the label `Recent`, so six rows say `Recent` six times.

## Do

1. **Crash toast.** Summary: "<App> closed unexpectedly", where <App> is the `Name=` of the desktop entry whose `Exec` binary matches the crashed exe (search `$XDG_DATA_HOME/applications` then `$XDG_DATA_DIRS`), else the program name with its first letter capitalised. Body: "Click to find out why. The check runs on this computer." Keep the `--exec` diagnose action and its arguments exactly. Urgency normal, not critical: a crash in a background helper should not pin a toast. The signal name stays out of the text; it is still passed to the diagnose action. Update `tests/test_crash_watch.sh` expectations and add one case where the desktop-entry name is used (a fixture `.desktop` in the test's temp data dir). `docs/agents/crash.md` changes with it.
2. **Media empty state.** Title "Nothing playing". No body text. If the shell knows the last player that was active this session, a button "Open <player>" that raises or launches it; if not, nothing else. Keep it simple: do not add persistence.
3. **Recent rows.** The empty-query list shows one "Recent" section heading above the recent apps instead of the label on every row. Commands already render under group headings (J48, see how the action scope draws them in `modules/koompi/overview/Search*.qml`); reuse that mechanism rather than adding a second one. Rows keep their own type label in every other list.
4. **Tests.** Crash: as above. Recent rows: `tests/test_search_commands.sh` or `tests/test_search_providers.sh` show how search results are tested; add an assertion that the empty query yields one heading and rows without the per-row label.

## Acceptance

- `test_crash_watch.sh` before/after output; the search assertion fails on `dev` and passes on your branch.
- Headless screenshot of the media panel with nothing playing (`ipc:mediaControls open`).
- Search does not render under headless KWin; say so and rely on the test for it.
- Full suite: no new failures.

## Out of scope

- The kernel's "Memory Shortage Avoided" notifications (another daemon sends them; grouping system notifications is Phase 2).

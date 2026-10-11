# J38: the assistant drawer answers "what is my work doing"

Audit: `docs/design/ux-audit-2026-10-07.md` section 3.6 and `docs/navigation.md` Roles (`:19`, `:21`, `:30-31`). Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.
Files owned:
- the drawer's top section in `modules/koompi/sidebarLeft/` (whatever J24 builds as the drawer);
- a new `modules/koompi/sidebarLeft/now/`;
- read-only use of `services/ai/ThreadStore.qml` and `services/ai/ToolRunner.qml`, plus small additions there that expose state (no behaviour change);
- `docs/navigation.md` Roles rows for Now;
- a new test.
Depends on: J24 (the 420 px assistant drawer with one thread store) merged, and J07 (sidebarLeft root) merged.
Shared with: J24's composer and thread view stay J24's. J38 adds the Now section above them and does not restyle them.

## Evidence (on `dev`)

- `docs/navigation.md:19,30-31`: Now is the left sidebar, "to become Quickwork's drawer: active tasks, approvals, recent artifacts, and task continuity". Until Quickwork exists the sidebar holds the inherited AI and translator tabs. `:21`: Quickwork is "not built", `Super+O` reserved.
- The state Now can show already exists:
  - `services/ai/ThreadStore.qml:25-37`: threads, the current one and `lastActiveId` (continuity);
  - `services/ai/ToolRunner.qml:132-149`: approval rules, and `:241`: a tool call waiting for approval (`functionPending`);
  - `ask_agent` runs (`:136-180`) are the long-running tasks.

## Do

1. A Now section at the top of the drawer, shown only when there is something in it:
   - **Running:** agent tasks in progress, with a one-line status and a stop.
   - **Waiting for you:** pending approvals, approvable inline with the same rules and wording as the in-thread card.
   - **Recent:** the last three threads, to continue where you left off.
   Empty means the drawer opens straight into the composer.
2. **Recent artifacts:** if tool results record the files they wrote, list the last few with Open and Show in folder. If they do not, say so in the report and leave it out. Do not add tracking for this job.
3. `Super+A` behaviour and the drawer's size are J24's. Now adds no binding.
4. Update the Roles row and paragraph to describe what Now shows once this lands.

## Tests (fail on `dev` first)

- A headless probe with fixture threads and a pending `ask_agent` approval:
  - the Now section lists the running task and the approval;
  - approving from Now resolves the same pending call the thread's card would;
  - with no fixtures, the section is absent.
- The network stays shimmed: no request leaves the machine.

## Acceptance

- shellshot renders of the drawer at 1920x1200 and 1366x768, dark and light: empty, and with a running task and an approval. Look at them in full.
- Test before/after output. Full suite: 0 failed (J15's flake aside).

## Out of scope

- Quickwork itself, and `Super+O`. Changing approval rules. New agent capabilities.

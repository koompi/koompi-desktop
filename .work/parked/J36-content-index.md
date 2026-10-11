# J36: Search finds what is inside your files, and the index never leaves the machine

Audit: `docs/design/ux-audit-2026-10-07.md` section 3.2 (S3, and the Phase 4 row of section 6). Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md`, `CONTEXT.md` (The Moat, the Thinks stack, The Floor, Reduced-local mode, the "silent cloud fallback" anti-term) and `shell-services/shelld/PROTOCOL.md` first.
Files owned:
- a new crate in the `shell-services` workspace (e.g. `shell-services/index`), wired into `koompi-shelld` as one service, or a sibling daemon if stage A shows that is better;
- its section of `shell-services/shelld/PROTOCOL.md`;
- the content-results provider in `services/FileSearch.qml`;
- a Privacy settings section (`modules/settings/PrivacyConfig.qml`);
- tests; `docs/agents/` notes.
Depends on: J23 (blended Search) merged before stage B's Search integration. Stage A can start any time.
Shared with: J23 owns `LauncherSearch.qml` and the result list. J36 gives it a query API and a result shape: path, title, snippet, mtime, score. J23 places the results.

## Evidence (on `dev`)

- `services/FileSearch.qml:66-82`: files are found by basename only, with `fd`, under `~`, at most 30, after a 250 ms debounce. Contents are never searched.
- `CONTEXT.md:9-19`: the index, models and data stay on-device by default; the context engine is layer L1 of the Thinks stack, "today ~0% built". `CONTEXT.md:21-28`: The Floor and Reduced-local mode (embedding and retrieval local, chat off).
- `shell-services/` is a Rust workspace of services behind one daemon (`koompi-shelld`, `PROTOCOL.md`: "Nothing runs until it is asked for", availability per service).
- The assistant's memory daemon (`koompi-agent-memd`, a separate repo, `sdata/install/setups/agent_memory.sh:13`) already runs fastembed locally. It is a candidate for semantic recall later, not a dependency of this job.

## Stage A: design note, then stop

Write `docs/design/content-index.md` (one sentence per line) and stop for the lead (the choice goes to Jev):

- what is indexed (default folders, file types and extractors present on a stock KOOMPI install) and what never is (hidden dirs, `.git`, caches, mail stores, encrypted vaults);
- storage: SQLite FTS5 or another embedded engine, and where it lives;
- update model: inotify or fanotify, initial crawl pacing, pause on battery via the `power` service, pause while the user types;
- budgets at The Floor: RAM resident, CPU during the crawl, disk per 10k documents, query latency p50/p95;
- privacy: no network access at all (prove it), index files mode 0600, a Privacy setting to pause, exclude folders and clear the index, and what a deleted file leaves behind (nothing);
- the query API on the `koompi-shelld` protocol, and the result shape J23 consumes.

## Stage B: build (after the lead's go)

1. The service, the shelld wiring and the Privacy section, as the note says.
2. `FileSearch.qml` gains content hits from the API. J23 puts them in Search's Files section with folder, date and a snippet; `Space` opens Quick Look (already in the tree as `koompi-quicklook`).

## Tests

- Rust unit tests for extraction, the crawl and the query (fixtures in a temp dir).
- An integration test:
  - index a fixture tree; find a word that occurs only inside a file;
  - delete it and it is gone;
  - an excluded folder is never read.
- The no-network proof: the daemon runs in a network namespace with no interfaces (or under a seccomp or `strace -e trace=network` check) and still passes.

## Acceptance

- Measured, not predicted:
  - crawl time and peak RSS for a 10k-file fixture;
  - idle RSS;
  - query p50/p95;
  - disk size;
  - CPU while paused on battery.
- Everything stays on the machine, shown by the no-network test.
- Full suite: 0 failed.

## Out of scope

- Semantic or embedding search (a later step through memd). Indexing outside `$HOME`. Cloud anything.

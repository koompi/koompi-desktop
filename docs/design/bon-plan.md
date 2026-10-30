# Bon: plan

Status: **plan only**, written 2026-10-16. Nothing is forked or built for KOOMPI. Facts checked 2026-10-16 against the sources linked and on the founder's machine.
Goal: KOOMPI's own terminal, built from Warp's open-source client, where the AI comes from the user's own subscription or key and nothing passes through Warp's servers.
A Google AI Pro user signs in once and asks; so does a ChatGPT Plus user; a user with an API key or a local model gets the same panel. Khmer renders correctly.
The name is the founder's, chosen 2026-10-16. In Khmer, bon (បុណ្យ) is a festival and merit; in French it means good.

## What Warp gives us, and what it does not

- **The client is open; the server is not.** Since 2026-04-28 the client is AGPL-3.0, with the UI framework crates (`warpui`, `warpui_core`) under MIT.
  The server, Drive, hosted sign-in and the agent are not open. Warp's FAQ: "Warp's built-in agent harness runs server-side and isn't open in this repo today."
- **Every agent turn goes to Warp.** `spawn_generate` in `app/src/ai/blocklist/controller/response_stream.rs` posts to `<server>/ai/multi-agent` with a Warp login token (`crates/warp_multi_agent_client/src/lib.rs`).
  Keys the user brings travel inside that request (`api_keys_for_request` in `crates/ai/src/api_keys.rs`), and Warp's own "Connect ChatGPT" is linked on Warp's server.
- **The open-source build still talks to Warp.** `app/src/bin/oss.rs` turns telemetry, crash reporting and auto-update off, but points at Warp's production server. Skipping sign-in turns all AI off.
- **What is already there for us:**
  - The terminal recognises 18 command-line agents (Codex, Gemini, Antigravity, Claude, Pi, OpenCode, Grok and more) in `app/src/terminal/cli_agent.rs`, and that works without an account.
  - An ACP client (Agent Client Protocol: one way for an app to host any coding agent) merged on 2026-10-09 ([#16332](https://github.com/warpdotdev/warp/pull/16332)), about 6,000 lines with tests, in `app/src/ai/agent_sdk/driver/harness/acp/`.
    Its `AcpTurnMapper` turns an outside agent's stream into Warp's own agent actions, so the panel, diffs and approvals work unchanged. Today it runs only for Warp's cloud agents.
  - ACP in the desktop app is on Warp's roadmap ([#7326](https://github.com/warpdotdev/warp/issues/7326); spec PR [#9380](https://github.com/warpdotdev/warp/pull/9380) open).
- **The size.** 1.78 million lines of Rust and 1,574 crates. Upstream merged 41 PRs in the week to 2026-10-16 and about 155 commits in 30 days.

Checked on the founder's machine on 2026-10-16 (master `53f8a71`):

- `cargo build -p warp --bin warp-oss` succeeds with only the Arch packages already installed (debug build, 13 min 43 s, 13 GB of build output, a 1 GB binary). A release build is not measured yet.
- In a nested KOOMPI session it runs natively on Wayland (`WARP_ENABLE_WAYLAND=1`; class `dev.warp.WarpOss`, not Xwayland). "Skip for now" gives a working terminal with no account.
- **Khmer output is broken.** `echo សួស្តី ពិភពលោក` prints as "សភ ពកពលក": vowel signs and subscripts are dropped. wezterm in the same session, with the same fonts, shapes it correctly.
- Not Bon's: zsh shows Khmer marks as `<17bd>` codes at the prompt in any terminal, because `COMBINING_CHARS` is off in KOOMPI's zsh config and in the founder's. That is a one-line fix in `dots/.config/zshrc.d/`, separate from this plan.

## How subscriptions reach Bon

The rule: **Bon never holds a subscription login.** The provider's own program signs in and keeps the token; Bon starts it and talks ACP to it.
Bon stores only API keys the user pastes, in the system keyring.

| Account | Route in Bon | Status |
|---|---|---|
| Google AI Pro / Ultra / free | Google's own ACP server, `antigravity-acp` in the [ACP registry](https://github.com/agentclientprotocol/registry/blob/main/antigravity-acp/agent.json) (authors "Google LLC", downloaded from dl.google.com, v1.4.0 on 2026-10-14). | **Verified 2026-10-16:** a 90-line client signed in with "Log in with Google", the server reported the tier as Google AI Pro, and answers came in 2–3 s. Over ACP it offers only Gemini 3.8 Flash; the `agy` CLI also offers Claude Opus 5.5 and Sonnet 5.5. |
| ChatGPT Plus / Pro | `codex-acp` (OpenAI, JetBrains, Zed; Apache-2.0), which signs in with the ChatGPT subscription. Later, Bon's own [Sign in with ChatGPT](https://developers.openai.com/siwc/token-sharing-open-source), self-serve for open-source local apps. | Not tested yet. Sign in with ChatGPT is a preview. |
| Claude Pro / Max | Only by typing `claude` in the terminal. Anthropic's terms of 2026-02-19 forbid subscription logins in any other product, the Agent SDK included. `claude-acp` works with an API key. | Policy, not code. |
| API keys and local models | OpenCode (MIT) over ACP: OpenRouter, DeepSeek, Ollama, LM Studio. | Not tested yet. |
| Pi | `pi-acp` (community, MIT). | Not tested yet. |

Google bans using Gemini CLI or Antigravity logins from other tools ([FAQ](https://geminicli.com/docs/resources/faq/); suspensions in 2026-02).
Starting Google's unchanged binary from the registry is what Zed and JetBrains do. A forum reply calling local wrapping compliant came from an account not shown as Google staff, so it is not relied on here.

## Decisions

- **D1, the fork's shape. Recommended: (a).**
  - (a) A light fork: Bon is upstream plus a small set of patches, rebased every week, with what we can offered back to Warp.
  - (b) A hard fork like [Leanterm](https://github.com/paezba/leanterm), which deleted about 1.2 million lines and stopped following upstream. Every later Warp fix would be ours to port.
- **D2, where the AI comes from. Recommended: (a).**
  - (a) ACP first: the providers' own agents, through the client Warp already merged. Little code of ours, and no tokens in our hands.
  - (b) Our own agent engine, as [OpenWarp](https://github.com/sasuke39/openwarp) did: a local stand-in for Warp's server. It owns prompts, tools and Warp's private protocol, and still lacks sub-agents, computer use and suggestions.
  - (c) Keep Warp's server. Then Bon is Warp with a new name, needing a Warp account, and AI stops when Warp says so.
- **D3, the first agent. Recommended: Antigravity.** It is the founder's plan, and its route is the only one verified end to end. Codex follows in the same phase.
- **D4, the repository. Recommended: `koompi/bon` on GitHub, a fork of `warpdotdev/warp`.** AGPL means the source must be public from the first build we ship, and anything built into Bon is AGPL too.
- **D5, when Bon becomes the default terminal. Recommended: only after the gates in Phase 5.** Until then wezterm stays the default and Bon ships beside it.
- **D6, what goes back to Warp. Recommended: the Khmer fix, desktop ACP if Warp has not shipped its own, and a product-name setting.** Contributing needs Warp's CLA.
- **D7, internal names. Recommended: keep them.** Crates stay `warp_*`; only the binary, app id, directories and the strings users see change.
  Renaming crates would touch most files and break every weekly rebase. No crate may be named `bon`: that is a popular Rust builder crate, and Warp already depends on it (`bon` 3.7.1).

## What Bon changes

1. **Identity.**
   - A new binary `bon`, made like `app/src/bin/oss.rs`, with app id `com.koompi.Bon`, its own log file and the `bon://` URL scheme; telemetry, crash reporting and auto-update off.
   - Its own desktop file and icon, so the bar shows "Bon" (a source build shows "Desktop" today).
   - Its settings and data must never mix with an installed Warp. Directories still derived from the channel (`~/.warp-oss`) move to Bon's own. Per-repository `.warp/` files (workflows, rules) keep working.
   - User-visible "Warp": 1,153 strings in 272 files. Change the surfaces people see first (window title, onboarding, settings, About, menus), and offer Warp a product-name setting so the rest becomes one line.
2. **No Warp account.**
   - Start without the sign-in slides.
   - Hide Drive, sharing, teams, cloud agents, credits and billing, and Warp's "Connect ChatGPT", through feature flags where they exist.
   - Make no request to Warp's servers at all, checked with a network namespace that has no route out.
3. **Local agents.**
   - At `spawn_generate`, send the turn to a local ACP agent instead of Warp's server, through the merged ACP client and `AcpTurnMapper`.
   - Conversations are stored locally; the merged code persists runs on Warp's server and that part changes.
   - An agent picker lists the agents that are installed. Signing in calls ACP `authenticate`, and the agent opens the browser itself.
   - Permission requests use Warp's existing approve and deny UI; file edits use its diff review.
4. **Getting the agents.**
   - Bon never downloads an agent silently. `antigravity-acp` alone is a 336 MB download that unpacks to about 1 GB.
   - KOOMPI installs them: `sdata/install/agents.sh` already installs Codex, Pi, Claude Code and Herdr user-locally. It gains `agy`, Google's ACP server, `codex-acp` and OpenCode, with sign-in left to each user, as today.
5. **Khmer.**
   - The grid keeps combining marks in `cell_with_zero_width` (`crates/warp_terminal/src/model/grid/cell.rs`), and text goes through cosmic-text, which can shape Khmer. Find where the marks are lost between the two.
   - Then test Khmer typing through fcitx5 (winit's IME is on in `crates/warpui/src/windowing/winit/window.rs`).
   - Upstream issue [#13719](https://github.com/warpdotdev/warp/issues/13719) is the same class of bug for Indian scripts.
6. **KOOMPI integration.**
   - Native Wayland on by default.
   - A Bon theme written by `applycolor.sh` from the wallpaper colours, as kitty's is.
   - The class added to the swallow regex in `general.lua`, and `bon` added to the terminal list in `variables.lua` (last until Phase 5).
   - Bon has no D-Bus menu, so the bar's global menu stays empty for it, as for wezterm.
7. **Packaging.** A `bon` PKGBUILD in `sdata/dist-arch/`, built from a tagged release. Release builds come from CI until the signed `[koompi]` repository exists (it is a skeleton today).

## Phases

### Phase 0: the fork and a baseline (about 1 week)

- Fork to `koompi/bon`. Keep upstream `master` untouched and the patches on a `bon` branch, one commit per change above.
- CI on Arch builds `bon` in release mode. A weekly job rebases onto upstream and reports conflicts.
- Measure against wezterm: release binary size, cold start, memory with three tabs, build time.
- A Khmer screenshot test in a nested session, like the repo's other nested tests, comparing Bon's rendering with wezterm's.

**Done when:** CI is green, the rebase job runs, the baseline numbers are recorded here, and the Khmer test fails for the right reason.

### Phase 1: Bon's identity, no account (about 1–2 weeks)

**Done when:** `bon` starts with no sign-in screen, shows "Bon" in the bar and the window title, uses only its own directories, and makes no connection to `*.warp.dev` from start to quit.

### Phase 2: Khmer (about 1–3 weeks; the cause is not found yet)

**Done when:** the Khmer screenshot test matches wezterm, Khmer typed through fcitx5 appears correctly in Bon's input editor, and the fix is offered upstream.

### Phase 3: AI through ACP (about 3–5 weeks)

Google first, on the founder's account, then Codex, OpenCode and Pi.

**Done when:**
- A Google AI Pro user picks "Google" once, signs in in the browser, asks for a change in a repository, reviews the diff in Bon's panel and approves a command.
- The same works for a ChatGPT Plus user through `codex-acp`, and offline with OpenCode and Ollama.
- Nothing reaches Warp's servers.
- If Warp ships desktop ACP first (#7326), Bon adopts theirs and drops its own.

### Phase 4: KOOMPI integration and the package (about 2 weeks)

**Done when:** on a fresh KOOMPI install, `pacman -S bon` gives a themed, native-Wayland Bon, `agents.sh` has installed the agents, and the first AI answer comes less than a minute after the user signs in.

### Phase 5: Bon becomes the default terminal (a gate, not work)

**Done when:**
- The Khmer test passes.
- The founder has used Bon daily for two weeks with no blocker.
- Its cold start and memory are within twice wezterm's.

Then `variables.lua` and `kdeglobals` put `bon` first, and wezterm stays installed.

### Later, not in this plan

- Bon's own Sign in with ChatGPT, for a native agent without Codex.
- Windows and macOS builds. The code supports them; KOOMPI does not need them.

About 8–13 weeks of one engineer's work. On top, the weekly rebase costs about half a day while Bon carries its own ACP code.

## Risks

- **Warp's direction.** The CLA lets Warp relicense future versions. Code released under the AGPL stays AGPL, so Bon can always continue from the last open release.
- **Upstream churn where Bon patches.** Five ACP PRs were open on 2026-10-16. Keep the seam patch small, and prefer Warp's desktop ACP once it lands.
- **Google's terms and server.** The ACP server's sign-in or models can change; Bon only starts Google's unchanged binary and never touches its token.
- **OpenAI's preview.** Sign in with ChatGPT's eligible plans and limits can change; `codex-acp` comes first for that reason.
- **Claude subscriptions cannot be used in Bon's panel.** Users of those plans type `claude` in the terminal; Bon's CLI-agent support still gives them notifications and rich input there.
- **Size.** A 1 GB debug binary, a release size not yet measured, and agents as large as 1 GB. Phase 0 measures; Phase 5's gate holds the line.
- **The name.**
  - "Bon" is free in Arch, the AUR and as `koompi/bon` on GitHub (checked 2026-10-16). Trademark registers (Cambodia's DIP and the USPTO, software class) are not checked; do that before announcing.
  - Bon must not use Warp's name or logo except to say it is based on Warp, with a disclaimer like Leanterm's. "Warp" is Denver Technologies, Inc.'s trademark.
- **Khmer may be deep.** If the marks are lost in the renderer rather than the grid, Phase 2 can grow. That is why it comes before the AI work and gates the default.

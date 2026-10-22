# KOOMPI AI agent: tuned harness, remote providers, computer and browser use

Plan, 2026-10-22. Founder's ask: apply the Harness² method to our agent and improve it, add remote providers including a ChatGPT subscription, add computer use and browser use. The founder took every recommendation below.

The agent today is described in `docs/agents/ai.md` and the code in `dots/.config/quickshell/koompi/services/ai/`. It runs inside the shell, there is no daemon, and the default local model is `gemma4-e4b` on LiteRT-LM (`127.0.0.1:9379`, 16k window, about 14 tok/s decode).

## Decisions

| # | Question | Taken |
| --- | --- | --- |
| D1 | Where the plan lives | Here, plus `~/.config/koompi/TODO.md` for open items; no `.work/` campaign |
| D2 | ChatGPT token store | `0600` file under `~/.local/state/koompi/ai/chatgpt/`, `flock` around refresh. OpenAI's guidance, and it works while the keyring is locked |
| D3 | Commercial use of the ChatGPT plan | Built on OpenAI's open-source, locally hosted route. Before KOOMPI ships it preinstalled on sold hardware, the founder files OpenAI's interest form |
| D4 | Model the harness is tuned for | `gemma4-e4b` (The Floor); `gemma4-e2b` and one remote model as regression checks |
| D5 | Improver model for tuning | Claude through the `claude` CLI, on synthetic tasks only, never user data |
| D6 | Browser the agent drives | Google Chrome (shipped in `koompi-apps`), CDP over `--remote-debugging-pipe`, no open port |
| D7 | The user's signed-in browser profile | Never in v1. The agent has its own profile, `~/.local/share/koompi-ai/browser` |
| D8 | Screenshots to remote models | Allowed with consent per session naming the provider; blocked under `policies.ai == 2` |
| D9 | Stop key for a Control session | Super+Shift+Escape (Super+Escape is Kiri's cancel, `hypr/custom/keybinds.lua:8`) |

## Milestones

- [x] **M0 Headless engine.** The real `Ai` services offscreen with an isolated HOME, driven by a job file, the thread out as JSON, and a prompt-directory override. Unblocks everything below.
- [x] **M1 Responses API.** `ResponsesApiStrategy.qml`: streamed text, function-call items, the system prompt as `instructions`, `store:false`.
- [x] **M2 ChatGPT sign-in.** `scripts/ai/chatgpt_auth.py` (`login`, `token`, `status`, `logout`): dynamic client registration, PKCE, loopback callback on `127.0.0.1`, rotating refresh under a lock. The request script fetches the token at run time; it never sits in QML or `request.sh`.
- [x] **M3 Providers in Settings > AI.** Local, ChatGPT plan ("Continue with ChatGPT", Manage usage, Sign out, "Using ChatGPT plan" by the picker), API-key providers, and a form for any OpenAI-compatible endpoint. OpenAI's error codes handled as their docs require. Built and tested against fakes; the real sign-in, the live error bodies and the Manage usage URL are still to check.
- [ ] **M4 Browser use and the Control session.** `browser.py` drives Chrome over the pipe; `BrowserService.qml` keeps it for the session. The safety shell ships here: indicator, stop key, take-over pause, refusals (lock screen, polkit, password fields, keyring, Settings > Privacy), confirmation for consequential actions, and taint (after untrusted content enters a turn, "always allow" is off for shell, config and `ask_agent`). `browser.py` is in; the tool, service and safety shell are not.
- [x] **M5 Harness tuning, set-up.** Tool descriptions move out of `ToolRegistry.qml` into files; a KOOMPI task set with deterministic checks (2/3 tune, 1/3 held out); a Harness² adapter (`BenchmarkAdapter`, pinned as a dev-only uv dependency) or a port of its loop. Taken: the port, in `tests/bench/ai/` (see Findings). The descriptions stay in `ToolRegistry.qml`; `KOOMPI_AI_TOOL_TEXT` replaces them for one run, which is all tuning needs.
- [x] **M6 Desktop, structured.** `hyprctl` windows plus AT-SPI trees, act by reference. `scripts/ai/desktop.py` and the `desktop` tool (`desktop-rules.js`, `DesktopService.qml`, `DesktopTool.qml`) share M4's Control pill, stop key, take-over pause and taint. Refused: the lock screen, auth and keyring prompts, password fields, every shell surface (Settings, the AI chat), terminals (shell work goes through `run_shell_command`) and browsers (the browser tool). Built and tested in nested Hyprland with a GTK fixture. Still to check on the live desktop: Qt and Chromium apps (they need `org.a11y.Status` `IsEnabled`), keys while a sidebar layer holds the keyboard, and the pill and take-over.
- [x] **M7 Desktop, pixels.** Screenshot with numbered marks; the model names a mark, never an x,y. `see` in `desktop.py` with `desktop_pixels.py`: one window through `grim -T`, marks from AT-SPI extents (the tree's refs) or, for an app with no tree, from connected edge regions; a click by mark through `zwlr_virtual_pointer_v1`; D8 in `screen-rules.js` (local free, remote with a per-chat consent card naming the provider, nothing remote under `policies.ai == 2`). Built and tested in nested Hyprland with a fixture and a fake model on 127.0.0.1. Still to check on the live desktop: extents of Qt, Chromium and client-side-decorated apps, the virtual pointer across several outputs and scales, full-output shell layers (the overlay with pinned widgets) refusing every click, and the consent card's look. Still to check with real models: remote vision in each wire format, and a remote model with no vision.
- [ ] **M8 Tuning sweep and adoption.** k=1 parallel, then k=2 sequential on failures. Adopt one prompt set only if held-out checks improve, nothing regresses and the prompt is no larger.

Order: M0, then M1 and M2 alongside it, M4, M5, M3, M6, M7, M8.

## Findings

**Vision on the local model** (2026-10-22). LiteRT-LM 0.18 turns an OpenAI `image_url` part with a base64 `data:` URL into an image (`litert_lm_cli/commands/serve/openai_common.py:422`). `gemma4-e4b`:

| Image | Asked | Answer | Prompt tokens | Wall |
| --- | --- | --- | --- | --- |
| 640x200, two lines | read every line | exact | 284 | 8.6 s cold |
| 1600x1000 mock mail window | subject, centre of Send | subject exact; Send at (878, 915), real (1410, 915) | 335 | 4.8 s |

It reads screens reliably and points badly. So browser and desktop act by accessibility reference, and the pixel layer uses marks.

**ChatGPT plan route.** OpenAI documents plan usage for open-source and locally hosted apps: first sign-in registers the client (`client_id=dynamic_agent_client`, `agent_name_hint`, `ext_agent_host_id`), loopback callback on `127.0.0.1` (only the port may vary; not `localhost`), scopes `openid profile email offline_access resource.invoke chatgpt.tokens.use.direct`, `resource=https://api.openai.com/v1`, access token about 1 h, rotating refresh token. Inference is `POST https://api.openai.com/v1/responses` with `stream:true`, `store:false`, full history in `input`, `instructions` instead of a system message, no `temperature`; function tools work, OpenAI's hosted computer-use tool does not. Sources: developers.openai.com/siwc/token-sharing-open-source and its sub-pages (sign-in, models-and-inference, preview-limitations, errors-and-recovery), developers.openai.com/siwc/ui-ux-guidelines.

**Harness².** github.com/google-research/harness2 at `1cfe254` (Apache-2.0, stdlib-only Python). It tunes eight harness files by Propose-Probe-Compose without ground truth and keeps a per-domain lesson library. One task at k=1 costs 4 agent rollouts and 3 improver sessions plus a reflection, too heavy for the user's machine and needing a strong improver, so it runs at development time on synthetic tasks and its result ships as our default prompt files.

**First bench run** (2026-10-22, `gemma4-e4b`, 24 tasks, repeat 2). The shipped prompt and tools passed 24 of 48 (held out 4 of 16). The failures were mostly the engine, not the prompt:

- *Tool routing.* Each turn is offered the tools that fit 1461 bytes, ranked by words of the user's turn found in a tool's name or description. Short turns ("How much does the E13 cost?", "Move my bar to the bottom") matched nothing, so nearly every turn got `recall`, `ask_agent` and `get_shell_config` by priority. Web questions went to `ask_agent`, and the setters were never offered. Fix: hints per tool, words a person says when they need it, which the model never sees (`toolRanking.js`).
- *No chaining.* The turn after a tool result went out with no tools, so read-then-set was impossible and e4b wrote its own call syntax into the reply. Fix: that turn keeps the turn's subset, still under the ceiling.
- *Config dump.* `get_shell_config` returned the whole config, about 14 KB with the system prompt in it. e4b went into compaction for minutes and still misread the bar's position. Fix: a bare call lists sections and keys; a `section` returns its values.
- *No year* in the date the prompt carries.
- *Memory types.* `remember` offered `profile, preference, fact, task`, the prompt named seven others, and the model sent none. Fix: an enum of the store's types, required.

With the first four fixes, 40 of 48 (held out 14 of 16); the memory fix then took both memory tasks from 0/2 to 2/2, measured on those tasks alone. Left for tuning, all prompt or tool text: the hostname question goes to `ask_agent` though the machine section has it, and a looked-up price is given without its source. Variance at temperature 0.5 is real: one task went 2/2 then 0/2 with an identical request, so judge a change at repeat 2 or more, never one rollout.

**First tuning round** (2026-10-23, k=1, agg, repeat 2, Claude as improver). Base: tune 26/32, held out 16/16. The procedure candidate `inv1` reached tune 30/32 with nothing lost and 24 bytes smaller: it labels `{HOSTNAME}` as the computer's network name, maps "I prefer X" to `preference`, confirms a stored memory in one line, and ends a web answer with its source. The knowledge candidate reached 28/32. Not adopted: the rule asks for a held-out gain, and the held-out split is already at 16/16, so no candidate can show one. The held-out tasks need to get harder before M8 can adopt anything; changing the rule is the founder's call.

# J24: one assistant in two sizes, speaking plainly

Audit: `docs/design/ux-audit-2026-10-07.md` section 3.6 (L1-L4). Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.

Depends on:
- J07 merged; `SidebarLeft.qml` becomes a lazy surface, and its detach logic is one of the cases J07 had to handle, so read the merged file first.
- J23 merged before this job removes the Translator tab, so translation is never missing from the desktop. Build in parallel, merge after.

Files owned:
- everything under `dots/.config/quickshell/koompi/modules/koompi/sidebarLeft/`
- everything under `modules/koompi/intelligence/`
- `services/ai/ToolRegistry.qml` and `services/ai/ToolRunner.qml`: tool summaries and approval wording only
- `modules/common/Appearance.qml`: only the sidebar width lines `:448-453`
- `modules/common/Config.qml`: only `sidebar.translator` (`:666-669`)
- `dots/.config/hypr/hyprland/keybinds.lua`: only line 48 (`SUPER + ALT + A`)
- `docs/manual/09-the-assistant.md`, the left-panel step of `modules/koompi/tour/steps.js` (`:61-67`), the Now row and left-sidebar rows of `docs/navigation.md`
- new tests

## Evidence (verified on `dev` at `9de7a575a`)

- Width (L1):
  - `Appearance.qml:448-453`: the left sidebar is 50% of the screen width, 60% when extended (690 or 750 px fallback). `SidebarLeft.qml:108-125` applies the fractions, so the live seat drew it 1162 px wide.
  - A third size exists: detach (`SidebarLeft.qml:13-19`, `:86-94`), bound to `SUPER + ALT + A` (`keybinds.lua:48`).
- Three AI surfaces (L2):
  - the sidebar chat;
  - the Intelligence window (`modules/koompi/intelligence/Intelligence.qml`: IPC `intelligence` with `toggle`, `open`, `close` and `pane(name)` at `:67-86`, bound to `SUPER + SHIFT + I` at `keybinds.lua:51`);
  - a Translator tab (`SidebarLeftContent.qml:16-19`, `:85-97`, behind `sidebar.translator.enable`, default false, `Config.qml:666-669`).
- One thread store already: both surfaces read `services/Ai.qml:38` (`conversation`) and `:172` (`threads`); `services/ai/ThreadStore.qml:26,36` holds `currentThreadId` and `currentThread`.
- Diagnostic language in the transcript (L3):
  - `sidebarLeft/aiChat/AiMessage.qml:390-402` prints `called <tool> <JSON arguments>` in monospace;
  - `services/ai/ToolRunner.qml:230,322` print "Ran this, you approved it before" and "Asked the agent, you approved it before";
  - `sidebarLeft/aiChat/MessageGroundingHeader.qml:20-30` puts "KOOMPI AI · local/remote/escalated agent · model" on every answer;
  - `aiChat/feedback/CorrectionAffordance.qml:102` reads "Suppressed";
  - `aiChat/MessageCitations.qml:75-76` already has the plain sentence ("Every source is on this machine. Nothing left it.").
- Text under 12 px: `Appearance.font.pixelSize.smallest` is `round(16 × 0.625) = 10 px` at the default `baseSize` 16 (`Appearance.qml:263-265`, `Config.qml:219`). It is used 44 times in 17 files under `sidebarLeft/` and `intelligence/`.
- The composer (L4): `aiChat/ChatComposer.qml` and `aiChat/composer/` (attach menu, command palette, model picker), a row of icons plus a `/` command language (`aiChat/ChatCommands.qml`).
- `modules/koompi/tour/steps.js:61-67` says the left panel "holds the assistant and the translator".

## Do

1. **The drawer** is 420 px wide on every screen. Drop the fractions and the extended mode.
   - Its header has **Open in window**. That sets the Intelligence window to the chat pane on the same `currentThreadId`, opens it and closes the drawer. Nothing is copied, because the store is shared.
   - Detach goes away: remove the detach mode and `SUPER + ALT + A`. `SUPER + SHIFT + I` stays the window's one key.
   - Decision made by this spec, recorded for the lead: two sizes, as the audit proposes, not three.
2. **Provenance behind one glyph.**
   - Each answer carries one info glyph. Opening it with a click or `Enter` reads in sentences: where it was answered ("on this machine by Gemma" / "by ox-alpha at tokenra.io"), whether anything left the device, which sources it used, and what you approved earlier.
   - The per-answer chips and lines move inside it: locality, "Suppressed", the approval lines.
   - Nothing about provenance is lost, only folded.
3. **Tool calls in words.**
   - Each tool in `ToolRegistry.qml` gets a past-tense summary ("Checked system resources", "Searched your files for \"report\"").
   - The transcript shows the summary, expandable to the arguments as readable `name: value` lines. Raw JSON appears only inside the expanded view, labelled as such.
4. **No text under 12 px,** Latin and Khmer, in the drawer and in the Intelligence window. Replace every `pixelSize.smallest` there. Check Khmer line height: no clipped vowel signs. Use the Khmer UI translation, or a message with Khmer text, in the renders.
5. **The composer** labels what it offers: the icon row gets text labels, or folds into one labelled "+" menu. The `/` commands are discoverable from a visible hint, not only by typing `/`.
6. **The Translator tab goes.** Translation lives in Search (J23). Remove `sidebar.translator` and the tab. Remove `language.translator` (`Config.qml:501-505`) only if J23 does not read it; check J23's merged code. If a user's stored config carries the key, follow `docs/agents/migrations.md`.
7. **Docs.**
   - `docs/manual/09-the-assistant.md`.
   - The tour step `steps.js:61-67`.
   - In `docs/navigation.md`, the Now row (the drawer is still where Quickwork and Now land later) and the left-sidebar Entry points and Keyboard map rows, with `SUPER + ALT + A` gone.

## Tests that fail first

- **Headless probe** (`tests/private-bus.conf`, its own runtime dir, Ai on a stub model as `tests/test_ai_*` do). Open the drawer at 1920 and at 1366 width. Assert:
  - the drawer is 420 px wide;
  - "Open in window" opens `intelligenceOpen` on the same thread id;
  - a seeded tool-call message shows the summary text and no `{`;
  - no visible `Text` in the drawer or the Intelligence window has `font.pixelSize < 12`.
  On `dev` the width is 960 at 1920 and `smallest` text exists.
- **Keybinds:** `SUPER + ALT + A` is gone, and `tests/test_manual_references.sh` and `tests/test_keybind_descriptions.sh` pass.
- The existing `tests/test_ai_*.sh` all still pass.

## Acceptance

- Renders at 1920x1200 and 1366x768, dark and light, of the drawer and the Intelligence window. Each holds:
  - a local answer and a remote answer, with the info glyph open;
  - an expanded tool call;
  - the composer;
  - Khmer text.
  Look at each in full; nothing under 12 px, nothing clipped.
- Keyboard only: open the drawer (`Super+A`), type, send, open provenance, open in window, close.
- Full suite: 0 failed (known J15 flake: say so if it is the only failure, and show it passing alone).

## Out of scope

- Now and Quickwork themselves (Phase 4), model choice, memory features, the Translate command (J23).

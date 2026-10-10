# J05: Settings stops sending people to a JSON file

Audit: `docs/design/ux-audit-2026-10-07.md` section 3.10. Read `/home/userx/workspace/koompi/koompi-desktop/.work/jobs/CONTRACT.md` first.

## Evidence

Live screenshot of Settings on 2026-10-07:
- The most prominent control, a filled pill at the top of the navigation, is "Config file" (`settings.qml`).
- A banner on the Quick page: "Not all options are available in this app. You should also check the config file by hitting the "Config file" button on the topleft corner or opening /home/userx/.config/koompi/config.json manually." with a "Copy path" button (`modules/settings/QuickConfig.qml`).

## Do

1. Remove the banner from the Quick page.
2. Demote "Config file": it leaves the top of the navigation and becomes an ordinary, unfilled item at the bottom of the navigation list labelled "Edit config file", with the same action. If the navigation is generated from `services/SettingsPages.qml`, put it where that list ends rather than special-casing it in two places.
3. **Test.** A test that fails on `dev`: render Settings headlessly (`shellshot.sh` with a `run:` step that starts `qs -p <worktree>/dots/.config/quickshell/koompi/settings.qml`, or a probe QML that instantiates the page), and assert from the probe or the QML tree that the banner text is absent and that the config item is the last navigation entry. Do not assert by grepping QML source.

## Acceptance

- Headless screenshot of Settings before and after.
- Test before/after output. Full suite: no new failures.

## Out of scope

- Renaming colour schemes, Hug/Float, search in Settings, startup time (Phases 1 and 3).

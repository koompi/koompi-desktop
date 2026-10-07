# Phase 2 draft for docs/navigation.md

The repo rule is that a new surface enters `docs/navigation.md` before any code.
This file holds the exact text to commit, in two edits.
Each Phase 2 job then moves its own rows from the new section into the main tables when it ships, and deletes them from the new section; the last job to land deletes the section.

## Edit 1: one sentence after the second paragraph of the Roles section

Insert after "Launchpad is deliberately gesture-only and takes no keyboard binding, so the two never compete for the same reflex." (currently line 27):

```markdown
Phase 2 changes several of these surfaces; what is decided but not yet built is in "Decided for Phase 2, not yet built" below, and the tables here change as each piece ships.
```

## Edit 2: a new section, inserted before "## Rules for adding to this model"

```markdown
## Decided for Phase 2, not yet built

Source: `docs/design/ux-audit-2026-10-07.md`, decisions D2, D3 and D4, and jobs J17 to J24 in the UX campaign.
Each row moves into the tables above when its job ships.

### Roles

The six roles stay six.
Two of them gain a second surface, and no new role is created.

| Role | Change | Surface | Opened by | State |
| --- | --- | --- | --- | --- |
| Overview | gains the app switcher, its keyboard reflex for "take me back to that app" | `modules/koompi/appSwitcher/` | `Alt+Tab` held | `appSwitcherOpen` |
| Overview | becomes Mission Control: the current desk's windows laid out large, a strip of occupied desks with a `+`, typing filters | `OverviewPanel.qml` | `Super+Tab`, 4-finger up and down following the fingers | `overviewOpen` |
| Today | splits in two: the Control Center holds the machine's switches | `modules/koompi/controlCenter/` | `Super+Alt+N`, its bar glyph | `controlCenterOpen` |
| Today | the right sidebar becomes the Notification Center: date, notifications grouped by app, a System group, then the next events, weather, to-do and timer | `SidebarRight.qml` | `Super+N`, the clock | `sidebarRightOpen` |
| Now | the left sidebar becomes one assistant: a 420 px drawer that opens the same thread in the Intelligence window | `SidebarLeft.qml` | `Super+A` | `sidebarLeftOpen` |
| Search | one ranked list with section headings (Top Hit, Applications, Commands and Settings, Files, Calculator, Clipboard); the sigils stay as filters | `SearchPanel.qml` | `Super` release | `searchOpen` |

The Control Center and the Notification Center are one role on two surfaces because they answer one question, what the machine is doing, from the same edge.
Opening either closes the other.
The app switcher joins Overview rather than founding a role: it answers "where are my windows" for the one window you want, and it claims no `Super` chord.

### Entry points

| Surface | Keyboard | Bar | Corner | Gesture | IPC |
| --- | --- | --- | --- | --- | --- |
| App switcher | `Alt+Tab`, `Alt+Shift+Tab` while held; a quick tap switches to the previous app without drawing | none | none | none | yes, `appSwitcher` |
| Control Center | `Super+Alt+N` | its own glyph, left of the clock | none | none | yes, `controlCenter` |
| Notification Center | `Super+N` | the clock; a dot on it while notifications are unread | top-right | none | yes, `sidebarRight` |
| Overview | `Super+Tab` | right-click on the workspaces widget | none | 4-finger up opens and down closes, following the fingers | yes |
| Assistant drawer | `Super+A`; its header's Open in window hands the thread to `Super+Shift+I`'s window | one button, as today | top-left | none | yes |

The panel button that wrapped the status indicators goes away.
The clock and the Control Center glyph are the only bar targets that open a panel, and the update glyph keeps its own hit area beside them.
`Super+Alt+A` (detach left sidebar) is removed: the assistant comes in two sizes, the drawer and the Intelligence window.

### Keyboard map

| Keys | Action |
| --- | --- |
| `Alt+Tab` | app switcher: next app; release Alt to switch |
| `Alt+Shift+Tab` | app switcher: previous app |
| `Q`, `Escape`, arrows while `Alt` holds the switcher | close the selected app, cancel, move |
| `Alt+grave` | next window of the current app, nothing drawn |
| `Super+Alt+N` | Control Center (was: the right sidebar's controls page) |

`Super+grave` stays the terminal widget; window cycling takes `Alt+grave`, the switcher's own modifier.

### Panel contract

| Surface | Grab | Keyboard focus |
| --- | --- | --- |
| Control Center | dismissable | gated on `controlCenterOpen` |
| Notification Center | dismissable, unchanged from the right sidebar | gated on `sidebarRightOpen` |
| App switcher | none: it lives while Alt is held and closes on release, `Escape` or a commit | `None`; its keys arrive as Hyprland binds in the `appswitcher` submap, so the window being left keeps focus until the switch |

### Workspaces

The bar and the overview strip draw the occupied desks of the current group, the active desk if it is empty, and one empty "new desk" slot, from one shared rule.
Desk numbers are never renumbered, so `Super+N` still means desk N, and an empty desk appears in the bar the moment it is focused.
`bar.workspaces.dynamic: false` brings back the fixed row of `bar.workspaces.shown`.
```

## Notes for the lead

- `Super+grave` versus `Alt+grave`: the audit named `Super+grave` for window cycling, but `keybinds.lua:60` binds it to the terminal widget. The draft and J17 use `Alt+grave`; overrule both together if Jev or the founder prefers otherwise.
- Removing `Super+Alt+A` (detach) is J24's call under the audit's "two sizes"; it is the only Phase 2 change that takes a key away.
- The gesture row assumes J19's step 6 lands. If it is split off, keep "fire at the end of the swipe" in the main Gestures table and move this row to the split job.

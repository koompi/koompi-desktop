# Navigation model

This document fixes which shell surface owns what, so a new feature has one obvious home and a shortcut has one meaning.
It describes the desktop as shipped, and marks separately what is decided but not yet built.
Where this document and the code disagree, the code is the defect.

Source of truth for the bindings themselves is `dots/.config/hypr/hyprland/keybinds.lua`, for gestures `dots/.config/hypr/hyprland/general.lua`, and for surface state `dots/.config/quickshell/koompi/GlobalStates.qml`.
The `Super+/` cheatsheet is generated from the `description` field of each bind, so a bind without a description is invisible to users.

## Roles

Five roles, and nothing else may claim a primary gesture or a bare `Super` chord.

| Role | Question it answers | Surface | Opened by | State |
| --- | --- | --- | --- | --- |
| Search | "take me to a thing" | `SearchPanel.qml` | `Super` release | `searchOpen` |
| Overview | "where are my windows" | `OverviewPanel.qml` | `Super+Tab`, 4-finger up/down | `overviewOpen` |
| Today | "what is my machine doing" | right sidebar, `SidebarRight.qml` | `Super+N` | `sidebarRightOpen` |
| Now | "what is my work doing" | left sidebar, `SidebarLeft.qml` | `Super+A` | `sidebarLeftOpen` |
| Launchpad | "show me everything installed" | `Launchpad.qml` | 4-finger spread only | `launchpadOpen` |

Search is the primary app launcher, and one ranked list.
A query with no prefix asks every provider and draws the answers under headings, in this order when they have rows: Top Hit (the single best match across providers), Applications, Windows, Commands and Settings, Files, Calculator, Clipboard (three at most).
Each section keeps five rows and a "Show all N" row that retypes the query inside that section's sigil, so the sigils stay as filters.
Web search is always the last row.
The ranking is `services/launcherSearch/ranking.js`: a name that is the query beats one that starts with it, then a word that starts with it, then one that contains it, and a tie goes to the earlier section.
A row that arrives late (files, after fd's 250 ms debounce, or a translation) joins its section, and neither the Top Hit nor the row under the keyboard cursor moves.
A file row shows its home-relative folder and its modified date, read for the whole result set by one `stat`, never a process per row.
With the keyboard cursor on a file row, `Space` toggles `koompi-quicklook` on it and `Escape` puts the preview away before it closes Search; in the typing box `Space` is a space.
The desktop's own switches are reached the same way: three letters find a command like night light, create system snapshot or screen snip, and a command with a Hyprland bind draws that chord as keycaps, taken from `HyprlandKeybinds` by the bind's description (`bind` in `services/commandTree/Entries.qml` and `Captures.qml`).
The action scope (`/`) with nothing typed after it lists every command under its group heading.
`translate <text>` runs the left sidebar's `trans -brief` call with the engine and languages from `language.translator`; the text goes to an online translator and the row says so, and Enter copies the result.
On the selected app row the desktop entry's actions are labelled buttons; unselected rows show none.
Groups are headings, not levels, so there is no drilling and no back key, and a command the machine cannot run is absent rather than greyed — a laptop with no fingerprint reader never sees the enrolment row.
An empty query with no prefix still answers with recent apps, under one Recent heading drawn by the same mechanism as a command group's, not a label on each row.
Launchpad is deliberately gesture-only and takes no keyboard binding, so the two never compete for the same reflex.
Phase 2 changes several of these surfaces; what is decided but not yet built is in "Decided for Phase 2, not yet built" below, and the tables here change as each piece ships.

One role is named for where it is going, not for what it is today.
**Now** is the left sidebar, which is to become a drawer for what your work is doing.
It still holds the inherited AI and translator tabs, and those are the thing being replaced rather than the thing being specified.

**Today** is the right sidebar, and it is built: a header carrying today's date, pin, settings and power, then one column.
Quick sliders and toggles come first, with an All controls row that opens the full grid as a drawer page.
Under the Today heading sit the weather, today's calendar events and the grouped notifications.
Under the Personal heading, Calendar, To Do and Timer are rows that open as drawer pages, so their widgets are built only while a page is open.

## Entry points

A surface gets one keyboard binding, at most one pointer target, and at most one gesture.
Anything beyond that has to earn its place, because every extra way in is another thing that can disagree about the open state.

The inventory below is what exists, not what is sanctioned.
The horizontal bar and the vertical bar are alternative bars, so a given session sees one column of these, not both.

| Surface | Keyboard | Bar | Corner | Gesture | IPC |
| --- | --- | --- | --- | --- | --- |
| Left sidebar | `Super+A` | one button, hidden unless AI or translator is enabled | top-left | none | yes |
| Right sidebar | `Super+N` | one button | top-right | none | yes |
| Overview | `Super+Tab` | right-click on the workspaces widget | none | 4-finger up or down | yes |
| Search | `Super` | none | none | none | yes |
| Launchpad | none, by decision | none | none | 4-finger spread and close | yes |
| Cheatsheet | `Super+/` | none | none | none | yes |
| Window actions | none, by decision | left-click the app identity in the left section | none | none | no |
| Snap preview | none of its own, rides `Super+drag` | none | none | none | no |
| Workspace hint | none | shown under the workspaces widget on a first run | none | none | no |
| Screensaver | none | none | none | none | yes, called by hypridle at 120 s idle and closed on resume; any key or pointer motion on it also closes it, and the lock replaces it |
| Bar popups: 1 agent usage, 2 battery, 3 pomodoro, 4 clock | `Super+Ctrl+1`..`4`, again or `Escape` to close | hover the widget | none | none | yes, `bar popup N`, `bar popupClose` |
| Update badge | none | its own glyph, no count, left of the right-panel button while updates are pending; click opens the updates popup (count, last check, Update now, Check again), click again or outside closes it, middle-click rechecks | none | none | no |

The update badge is deliberately not part of the right-panel button: it used to sit inside it, and a click aimed at the panel could start a system upgrade.
It is its own item with its own hit area, shows a glyph and never a count, and the upgrade runs only from the popup's Update now button, which opens a floating terminal running `koompi update` through Hyprland's Lua `hl.dsp.exec_cmd`.
A bar popup hangs under the widget it belongs to and is clamped to the screen the bar is on, so the clock at the far right gets a popup that ends at the screen edge instead of running off it.

Getting to one bar button per sidebar took a change on 2026-07-30.
Three bar sections were left-click toggles for a sidebar on top of the dedicated button inside that same section: the right section of the horizontal bar, and both the top and bottom sections of the vertical bar.
The consequence was that clicking the clock, the Pomodoro timer, or a gap between tray icons opened a sidebar.
The horizontal bar's left section already did it correctly, with `acceptedButtons: Qt.NoButton` and a comment saying clicks belong to the dedicated button, so the fix was to make the other three match it.
Those sections still exist for hover and for scroll-to-change-volume or brightness, which are wheel and hover behaviours and survive `NoButton`.

The window actions menu takes the one pointer path the app identity had spare, so a window's own actions are reachable without knowing a bind.
Left-clicking the icon, app name, and title opens close, float, fullscreen, pin, and move to workspace for the focused window, and clicking again closes it.
That is a click on a dedicated item, which is what the left section's `acceptedButtons: Qt.NoButton` reserves clicks for, so the section itself still opens nothing.
Right-click on the identity stays free, and the menu takes no keyboard binding and no gesture.
Each entry shows the bind that does the same thing, which is the only place the window binds appear outside `Super+/`.
It exists on the horizontal bar only, because the vertical bar shows no window identity to hang it off.
`windows.actionsMenu` turns it off, default true.

While an app is starting, the same identity answers for it, so Enter is never met with nothing.
Its icon and name show over "Opening…" and pulse, from the moment of the launch until a window of that app maps or 8 s have passed, and then the identity is the focused window again.
A window counts as the app's when it is the launched process, when its class resolves to the same desktop entry (`dolphin` on xcb and `org.kde.dolphin` on Wayland are one), when it carries the entry's `StartupWMClass`, or when its class is what was launched; it has to be a window that first showed up after the launch began, however late the shell heard of the launch.
An app that raises the window it already has maps nothing, so the focus landing on a matching window ends the launch too.
A window ends one launch for as long as it exists, and one focus move ends one, so starting an app twice shows "Opening" until its second window arrives.
Several launches at once, which is how session restore starts its apps, are kept up to eight, the oldest forgotten first, and the bar shows the newest one still waiting.
Each ends at its own window in whatever order the windows come, and one that never maps ends at its own 8 s without holding another up, though while it is the newest the bar keeps showing it.
An app that runs in a terminal is not announced at all, because its window is the terminal's.
Search, the Launchpad, the media controls and the dock tell the shell themselves, through `LauncherSearch.launch`.
A key bind tells it through `koompi-launch`, which makes one background `qs ipc call launch begin` and never waits for it.
While it shows, the focused window's menus and actions step aside, because they belong to the window being left, and the identity is not a click target.
The pulse dims the icon and the name and never the "Opening…" line, and never below 70% opacity, which keeps the name at 4.5:1 contrast on the dark and the light palette; Reduce Motion holds that dimmest state instead of pulsing.
With no window on the desktop the identity reads "Desktop" and nothing under it, because the bar's centre already shows the workspace.

The snap preview takes no input path at all.
`Super+drag` already moves a window, and `keybinds.lua` gives that same chord a second, `transparent` bind carrying `quickshell:snapPreviewDrag`, so the shell learns when a drag starts and ends without the drag itself changing.
While one is running, pushing the pointer into a screen edge draws the rectangle the window will take, and releasing puts it there: a side gives a half, a corner a quarter, the top edge the whole usable area.
The bottom edge alone does nothing, because that is where the dock is.
The threshold is 24px, small enough that dragging a tiled window to the far edge to swap it with the window there still reads as a swap rather than a snap.
Nothing new is added to the pointer, the wheel, or any gesture, and the preview window carries an empty input mask so it cannot take a click even while it is up.
`windows.snapPreview` turns it off, default true; with it off the global shortcut is never registered and the bind above dispatches into nothing.

The first-run workspace hint deliberately does not take the workspaces widget's right-click, which belongs to Overview, or its wheel, which steps workspaces.
It is dismissed by its own button and by nothing else, so no existing click, drag, or key changes meaning while it is up.
`windows.workspaceHelp` turns it off, default true.

This matters more for the right sidebar than the count suggests.
Opening it runs `GlobalStates.onSidebarRightOpenChanged`, which times out every popup at once, so the toasts get out of the way.
A notification counts as read once it has been seen, so the unread count is zeroed only after the panel has stayed open for one second; closing it sooner leaves the count and the badge as they were, and an accidental open costs nothing.
No notification is discarded by either step: `Notifications.markAllRead()` only sets `unread` to zero, and `timeoutAll()` only takes notifications off the popup layer.

## Edges

The left edge belongs to work continuity, the right edge to system state.
An edge never opens something from the other side.

| Edge | Opens | Live by default |
| --- | --- | --- |
| Top-left corner, 250x5 px | left sidebar | yes |
| Top-right corner, 250x5 px | right sidebar | yes |
| Bottom corners | same, mirrored | no, `sidebar.cornerOpen.bottom` defaults to false |

Corner activation as a whole is `sidebar.cornerOpen.enable`, default true, and only the corner pair matching `cornerOpen.bottom` hosts a hot corner.
A corner window exists only while it has a job: drawing the fake screen rounding (`appearance.fakeScreenRounding`), or hosting its hot corner.
The jobs are independent, so the hot corners work with the rounding off, and there each corner window is exactly its 250x5 region.
Under a fullscreen window the hot corners are off, and so is the rounding unless `fakeScreenRounding` is 1 (always).
A corner fires on a push: the pointer has to move inside the corner window after entering it, and it fires once per visit, so a pointer that crosses the last two pixels in more than one move does not open the sidebar and shut it again.
Entering the window, or finding the pointer resting in it when a sidebar closes or the window appears, does not fire it, so a sidebar closed over IPC or with `Escape` stays closed.

## Gestures

| Gesture | Action |
| --- | --- |
| 3-finger swipe | move window |
| 3-finger pinch | fullscreen |
| 4-finger horizontal | switch workspace, walking numeric neighbours |
| 4-finger up or down | Overview |
| 4-finger spread | open Launchpad |
| 4-finger close | close Launchpad |

Launchpad is bound as separate open and close gestures rather than one toggle, so repeating the same motion never flaps it shut.
Hyprland's own direction names are inverted here: `pinchin` fires when the fingers move apart.

## Keyboard map

Only the primary bind is listed.
Many shell binds have a second copy guarded by `qs ipc call TEST_ALIVE ||` that runs a standalone fallback when Quickshell is not up, which is a redundancy mechanism rather than a separate binding.

### Shell surfaces

| Keys | Action |
| --- | --- |
| `Super` | Search |
| `Super+Tab` | Overview |
| `Super+A` | left sidebar |
| `Super+Alt+A` | detach left sidebar |
| `Super+N` | right sidebar |
| `Super+,` | dismiss the newest notification toast (it stays in the right sidebar's history) |
| `Super+Shift+,` | dismiss every toast |
| `Super+Alt+,` | open the newest toast: its default action, then dismissed |
| `Super+Shift+Alt+,` | notification history, the right sidebar |
| `Super+V` | clipboard history |
| `Super+.` | emoji |
| `Super+/` | cheatsheet |
| `Super+K` | on-screen keyboard |
| `Super+M` | media controls |
| `Super+G` | widget overlay |
| `Super+J` | bar |
| `Ctrl+Alt+Delete` | session menu |
| `Ctrl+Super+T` | wallpaper selector |
| `Ctrl+Super+Alt+T` | random wallpaper |
| `Ctrl+Super+Shift+D` | light/dark mode |
| `Ctrl+Super+P` | cycle panel family |
| `Ctrl+Super+R` | restart the shell |
| `Super+Alt+F1` | virtual machine mode, every key passes through until pressed again |

Clipboard and emoji belong to Search, not to Overview.
They set their own flags rather than aliasing `searchOpen`, which is what makes `Super+V` then `Super+.` switch mode instead of toggling the panel shut.

### Window

| Keys | Action |
| --- | --- |
| `Super+drag` | move, and drop into a screen edge to take that half |
| `Super+right-drag` | resize |
| `Super+arrows` | focus in direction |
| `Super+Shift+arrows` | move in direction |
| `Super+Q` | close |
| `Super+Shift+Alt+Q` | force quit |
| `Super+D` | maximize |
| `Super+F` | fullscreen |
| `Super+Alt+F` | fullscreen spoof |
| `Super+P` | pin |
| `Super+Alt+Space` | float or tile this window |
| `Super+Shift+Space` | stacking or tiling desktop |
| `Super+;` and `Super+'` | split ratio |
| `Super+Alt+1..0` | send to workspace |
| `Super+Shift+PageUp/PageDown` | send to workspace left/right |
| `Super+Alt+S` | send to scratchpad |

`Alt+F4` is caught and answered with a notification pointing at `Super+Q`, and is left non-consuming so Windows VMs still receive it.

### Workspace

| Keys | Action |
| --- | --- |
| `Super+1..0` | focus workspace |
| `Ctrl+Super+Left/Right` | focus workspace left/right |
| `Super+PageUp/PageDown` | focus workspace left/right |
| `Super+scroll` | focus workspace left (scroll up) or right (scroll down) |
| `Super+S` | scratchpad |
| `Ctrl+Super+S` | special workspace |

Number binds are duplicated on raw keycodes and on the keypad, because some layouts report number keys as other characters.

### Utilities

| Keys | Action |
| --- | --- |
| `Print` and `Super+Shift+S` | screen snip: drag a region, or take the whole screen from its toolbar |
| `Shift+Print` | whole screen, saved to Pictures/Screenshots and copied, with a notification |
| `Ctrl+Print` | the same, silently |
| `Super+Shift+A` | region to image search |
| `Super+Shift+X` | region to text, OCR |
| `Super+Shift+T` | translate screen content |
| `Super+Shift+C` | pick colour |
| `Super+Shift+R` | record region |
| `Super+Shift+Alt+R` | record screen with sound |
| `Super+Space` | switch keyboard layout, EN and KM |
| `Super+-` and `Super+=` | screen zoom |

### Media

| Keys | Action |
| --- | --- |
| `Super+Shift+P` | play or pause |
| `Super+Shift+N` | next track |
| `Super+Shift+B` | previous track |
| `Super+Shift+M` | mute output |
| `Super+Alt+M` | mute microphone |

The `XF86Audio*` and `XF86MonBrightness*` keys carry the same actions and are marked `locked` so they work on the lock screen.

### Session

| Keys | Action |
| --- | --- |
| `Super+L` | lock |
| `Super+Shift+L` | sleep |
| lid close | lock, unless an external monitor is attached; suspend stays with logind and Keep awake still blocks it |
| `Ctrl+Shift+Alt+Super+Delete` | shut down |

### Apps

| Keys | Action |
| --- | --- |
| `Super+Return`, `Super+T` | terminal |
| `Super+E` | file manager |
| `Super+W` | browser |
| `Super+C` | code editor |
| `Super+X` | text editor |
| `Super+I` | settings |
| `Ctrl+Shift+Escape` | task manager |
| `Super+`` ` `` | terminal panel |
| `Super+\` | system monitor panel |
| `Super+Y` | Telegram panel |

App binds are the one group that may grow, because they name what the user installed rather than what the shell owns.
Anything opened as a scratchpad panel rather than a normal window is a shell surface and belongs to a role above.

Every app bind, and every launch from Search, the Launchpad, the dock, the waffle start menu and taskbar, and a restored session, goes through `koompi-launch`, which starts the app as its own `app-<id>-<n>.scope` in the user manager's `app.slice` with the session environment intact.
That is what lets `systemd-oomd` kill one app under memory pressure instead of the whole session, because the session scope that holds Hyprland, the shell, hypridle and the wallpaper pipeline is never a candidate.
A bind for something the session cannot lose keeps `hl.dsp.exec_cmd` and stays out of `app.slice`.

`koompi-launch` also tells the running shell what is opening, in one background call before it starts the app, so the bar's app identity can say "Opening" until the window maps.
The call names the launch id, the program that will own the window (for `launch_first_available.sh`, the candidate it will pick), the pid, which `exec` keeps, and the time the launch began, so a terminal whose window maps before the call has reached the shell still ends it.
A shell surface that already told the shell passes `--registered`, and a launch inside a terminal says nothing, because its window is the terminal's.
No shell running is silent, and any other failure is a line in the journal under `koompi-launch`.

`koompi-launch` also chooses the platform of the Qt apps it starts.
Qt exports a menubar to the bar only on X11, so Dolphin, Okular, Konsole and Ark start with `QT_QPA_PLATFORM=xcb` and show their menus in the bar, and every other Qt app runs on Wayland with its menus inside its own window.
The session default in `hyprland/env.lua` is `wayland;xcb`, and the list is `xcb_menu_apps` at the top of `koompi-launch`.
The shell itself runs with `QT_QPA_PLATFORM=wayland` and passes it to what it starts, so `koompi-launch` turns an inherited bare `wayland` into `wayland;xcb`, and a Qt app without a Wayland plugin still starts from Search, the Launchpad, the dock, the waffle start menu and taskbar, and a restored session.
An app started outside `koompi-launch`, from a terminal or by D-Bus activation, runs on the platform of whatever started it, usually Wayland, and then has no menu in the bar.
A window rule for a Qt app has to match its class on both platforms, because the same app reports `kdialog` on xcb and `org.kde.kdialog` on Wayland.
The dock and a restored session match a window to its app by desktop entry, not by class.
A pinned `org.kde.dolphin` and a running X11 `dolphin` are one dock entry, and a saved `dolphin` claims the window that `org.kde.dolphin` opens.
A class with no entry to find (`kdialog`, `kdeconnect.app`) matches by its name without KDE's `org.kde.` prefix.
A window that reports no class has no entry: looking an empty class up answers with an arbitrary app, so the dock, the waffle taskbar and the media panel skip the lookup.
A restored session skips a saved window whose entry is `NoDisplay`, such as `kdialog`, which opens nothing when started bare, as it skips one with no entry.

### Kiri

Kiri's voice binds live in `dots/.config/hypr/custom/keybinds.lua`, which is user-owned and never overwritten by an update.
The migration `sdata/migrations/*-custom-keybind-descriptions.sh` brings the descriptions of the shipped lines in an existing copy up to the current wording: it rewrites only a line that is still exactly as KOOMPI shipped it, after a backup under `~/.local/state/koompi/backups/`, and leaves an edited or deleted line alone.

| Keys | Action |
| --- | --- |
| AI key, `Super+Shift+code:201` | English dictation |
| AI key with Alt | Khmer dictation |
| `Super+Shift+K` | Khmer dictation |
| `Super+Escape` | cancel dictation |
| `Super+Alt+K` | Kiri settings |

## Super on its own

Search opens when `Super` is *released*, which makes every other `Super` chord ambiguous until the release arrives.
The resolution is that pressing anything else while `Super` is held cancels the pending toggle.
Hyprland spells this `binditn = SUPER, catchall`, which `hl.bind` rejects, so `keybinds.lua` wraps `hl.bind` and gives every `Super` chord a companion bind carrying `quickshell:searchToggleReleaseInterrupt`.

Two rules follow, and both have been got wrong before.

The wrapper must stay installed for the rest of the config, including `custom/keybinds.lua`, or a user's own `Super` chord opens Search on release.

The only chord exempt is `Super`'s own keysym, `SUPER_L` and `SUPER_R`, because that press is what arms the toggle.
Mouse buttons are not exempt.
`Super+drag` is a chord like any other, and exempting it left the toggle armed for the whole drag, so letting go of `Super` opened Search over the window just moved.

## Panel contract

One surface, one owner of its open state, one focus grab, and keyboard focus only while open.

A closed surface does not exist.
`LazySurface` in `modules/common/` builds a surface's window the moment its open flag turns on and releases it `keepWarm` after the flag turns off, two minutes unless the surface says otherwise, so open, close, open inside that time is one instance.
The `IpcHandler`, the `GlobalShortcut`s and the state stay in the always-built `Scope` beside it, which is why keys and IPC still work with no window, and code outside the window reaches it as `surface.item`, never by an id inside it.
A window built while its flag is already on never saw the flag change, so what it does when opened it also does from `Component.onCompleted`.
The Launchpad, Search, Overview, the cheatsheet, both sidebars, the media controls, the session menu, the screensaver, the tour, the polkit prompt, the screen translator and the Settings window are built this way.
Settings is hosted by the shell: `koompi-settings` asks the running shell over IPC (`settings toggle`, or `settings page <name>`), and only when that call fails does it start the standalone `settings.qml`, which hosts the same `SettingsContent`.
Each of them but the polkit prompt reports `built`, whether its `LazySurface` holds an instance, and `tests/test_lazy_surfaces.sh` reads it while the surface is closed, open and just closed.
The polkit prompt is left out of that test because its agent registers on the system bus.

The shared mechanism is the `GlobalFocusGrab` singleton in `services/`.
A surface calls `addDismissable` when it becomes visible and `removeDismissable` when it stops, and closes itself on the singleton's `dismissed` signal.
A surface that should be inside the grab but must not be closed by a click outside, such as the bar and the on-screen keyboard, registers with `addPersistent` instead.
The grab covers the persistent windows too once the keyboard is inside a dismissable window, or none of them takes the keyboard, and `focusIn` decides that by climbing from the window's one focused item to its content item.
It must never visit every item below the content item: a binding depends on everything it reads, so a walk reruns for each item added while a window is built, and a cheatsheet built on open stayed blank for 8 s with the main thread pinned.
`tests/test_grab_binding.sh` checks the list against the old walk and the cost of a cold open; a click outside, which needs a pointer, is not in it.
`SearchPanel.qml` and `OverviewPanel.qml` are the reference implementations.

Conformance as of 2026-07-30:

| Surface | Grab | Keyboard focus |
| --- | --- | --- |
| Search | dismissable | gated on `searchOpen` |
| Overview | dismissable | gated on `overviewOpen` |
| Right sidebar | dismissable | gated on `sidebarRightOpen` |
| Left sidebar | dismissable | unconditional `OnDemand`, harmless because the window is gated on `sidebarLeftOpen` |
| Wallpaper selector | dismissable | unconditional `OnDemand`, window gated by its loader |
| Media controls | dismissable | not set |
| Bar popups | dismissable while keyboard-opened or click-pinned | `OnDemand` while keyboard-opened, so `Escape` reaches it |
| Cheatsheet | dismissable | gated on `cheatsheetOpen` |
| On-screen keyboard | persistent, correctly | commented out |
| Global menu | own `HyprlandFocusGrab` over the bar and every open popup | bar takes focus only while a menu is open |
| Window actions menu | own `HyprlandFocusGrab` over the bar and every open popup | bar takes focus only while a menu is open |
| Snap preview | none needed, empty input mask | `None` |
| Workspace hint | none, dismissed by its own button only | `None` |
| Launchpad | none needed, see below | gated on `launchpadOpen`, `Exclusive` |
| Widget overlay | own grab, left `active: false` | conditional, pinned widgets stay up by design |
| Region selector | none, modal capture surface | unconditional `OnDemand` |
| Screen translator | none, modal capture surface | unconditional `OnDemand` |
| Session menu | none, modal | `Exclusive`, loader-gated |
| Tour | persistent, deliberately | gated on `tourOpen` |

An unconditional `OnDemand` is not by itself a bug: a layer surface whose `visible` is gated on its own flag has no surface to focus while closed.
`OnDemand` is also the correct value rather than `Exclusive`, because since Hyprland 0.49 `Exclusive` breaks click-outside-to-close.

`GlobalFocusGrab` is only meaningful for a surface a click can land beside.
Launchpad and the modal capture surfaces cover the whole screen and dismiss themselves from their own input, so their absence from the grab is correct rather than missing.
Launchpad closes on a click anywhere on its background and on `Escape`, and the region selector and screen translator close on `Escape`.
The snap preview and the first-run workspace hint are absent for the same reason read the other way: the preview accepts no input at all, and the hint is masked to its own rectangle, so a click beside either lands on whatever is underneath and neither has anything to dismiss.

A surface that is fullscreen but masked to a smaller item, like the cheatsheet, is the case that does need the grab: outside the mask the click reaches the window beneath, and the grab is the only thing that notices.

The remaining gap is the one surface whose keyboard focus is set but not gated.
The wallpaper selector and the left sidebar both ask for `OnDemand` unconditionally, which is currently harmless and will stop being harmless the moment either window stays mapped beyond a single open.
A warm `LazySurface` window is built but not mapped, because a layer window that is not visible has no surface, so it does not count.

## App icons

Every app icon the shell draws goes through `AppIconPlate` (`modules/common/widgets`): the Launchpad, Search results, the dock, the Overview, the bar's workspace and active-window icons, and the waffle taskbar, start menu, task view and window previews.
`tests/test_icon_plate_sites.sh` lists those sites and fails on one that draws an icon around the plate.

The plate is a squircle whose corner is 28 % of its side and follows `rounding_power` (2.5), filled with the highest surface layer in dark mode and white in light, with a 1 px edge and an elevation-1 shadow.
An icon sits at 72 % of the plate.
When the active icon theme draws the icon itself and declares a full-bleed body (`app-icon-plate.js` lists the themes, WhiteSur-green at 6.25 % to 93.75 % of the canvas), the icon is cut to the squircle instead, so its body fills the plate and any overhang is clipped.
The theme comes from `QS_ICON_THEME`, else `[Icons] Theme` in `kdeglobals`, and a theme with no entry is never masked.
An icon that resolves to nothing (including `image-missing`) shows the first letter of the app's name on the plate.

The plate's shadow and each masked icon are drawn once into a texture (`AppIconPlates`, keyed by size, colours and icon) and every plate reuses it, so nothing runs a shader per plate per frame.
`tests/test_icon_plate_render.sh` counts the renders: sixteen animated plates cost one plate texture and one mask per distinct icon, and a second grid of the same icons costs none.
Sizes snap up to 16, 24, 32, 48, 64, 96, 128, 192 or 256 for the texture and are scaled to the size asked for.

## Motion

One budget for every surface, from decision D6 of the 2026-10-07 audit: a panel or popup arrives in 200 ms and leaves in 150, a small move takes 120, the workspace slide takes 300, and nothing overshoots.
The shell's half is the `animation` roles and the duration ladder in `modules/common/Appearance.qml`, and Hyprland's half is the leaves in `hyprland/general.lua`.
`tests/test_motion.sh` and `tests/test_motion_hypr.sh` hold both, so a surface that picks a role instead of a number is on the budget without a decision.

Search is a layer Hyprland does not animate, so its motion is the shell's alone.
The right sidebar arrives and leaves through Hyprland's layer leaves, and its drawer pages through the shell's.

`appearance.reduceMotion` (Settings, Quick, off by default) stops every spatial move in the shell, leaves fades at 100 ms, and turns Hyprland's animations off.
Hyprland's half goes through `services/HyprlandModes.qml`, which also owns Game mode's hold on the same option, so neither can undo the other.
The waffle panel family shares the ladder, so Reduce Motion reaches it the same way: with it on, every step of the ladder but `snap` is 0, and `Looks.transition`, `WStackView` and the bar panels' close follow.
A step is therefore never a timer interval, so a Timer that needs a number writes it (`tests/test_motion.sh` fails on one that borrows a step).
A loop whose duration can reach 0 stops under Reduce Motion, as `ThinkingIndicator` and the lock screen's fingerprint pulse do: `tests/test_motion.sh` reads every `loops: Animation.Infinite` in the shell and fails on one that borrows a step or a spatial role without a `running` that checks `reduceMotion`.

## The tour is a utility surface, not a role

`20260804-guided-tour` adds a guided walkthrough of the whole desktop, and it joins **no** role.
The rule below says a new capability joins an existing role or this document changes first, so the exception is worth stating rather than leaving to be rediscovered: the Roles table describes the six surfaces that may claim a primary gesture or a bare `Super` chord, and the model already carries utility surfaces outside it - the cheatsheet, the session menu, the wallpaper selector.
The tour joins that category. The Roles table stays at six.

Its entry point is `SUPER + SHIFT + Slash`, beside the cheatsheet on purpose: the tour is what a new user needs before the cheatsheet means anything, and the cheatsheet is what they reach for afterwards.

It registers **persistent** rather than dismissable, which is the one place it departs from every other non-bar surface.
Each of its steps opens the real surface it is describing, and nearly all of those are dismissable; a dismissable tour would be closed by the shared grab the moment it demonstrated anything.
That is the same reason the bar and the on-screen keyboard are persistent.

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

## Rules for adding to this model

A new capability joins an existing role.
If it does not fit one, the model is wrong and this document changes first.

A new bind carries a `description` prefixed with its group, or it will not appear in the cheatsheet.
Binds in a group that share a description are one cheatsheet row listing every chord, simplest first, so a second chord for an action reuses its description word for word.
A description says what happens and never names its keys, because the sheet prints the keys beside it.
The AI key sends Super and Shift itself and Hyprland sees `SUPER + SHIFT + code:201`, so the sheet prints that chord as `AI`, and `Alt + AI` with Alt; no other key drops its modifiers.
A run of numbered or directional binds (`Workspace: Focus 1` to `10`, `Window: Focus Left` to `Down`) becomes one row only when each key is the number or direction its own description names.
The sheet keeps every row inside its column: a long description wraps and a wide chord wraps, and the page scrolls, with no scrollbar, when the rows outgrow the panel.
On a screen under about 1420x890 the panel stops short of the screen edges and the bar: the Keybinds page scrolls as before and the Elements page makes its tiles smaller (down to 66x56 at 1366x768) so the whole table stays in view.

A new panel registers with `GlobalFocusGrab` and gates `WlrLayershell.keyboardFocus` on its own open flag, both, not one.
Its window is built through `LazySurface`, so it does not exist while it is closed.

A surface gets exactly one keyboard entry point.
Extra ways in belong to pointer and gesture, and each of those needs a reason to exist beyond being possible.

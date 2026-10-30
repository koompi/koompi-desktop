-- ######## Window rules ########

-- Disable blur for every window (the `.*` also covers the empty class/title
-- that xwayland context menus report)
hl.window_rule({match = {class = ".*" }, no_blur = true })

-- Floating
-- Signature capture/review are transient dialogs; tiled they leave dead space.
hl.window_rule({match = {title = "^(Capture signature)$" },                  center = true})
hl.window_rule({match = {title = "^(Capture signature)$" },                  float = true})
hl.window_rule({match = {title = "^(Capture signature)$" },                  size = {960, 660} })
hl.window_rule({match = {title = "^(Signature preview)$" },                  center = true})
hl.window_rule({match = {title = "^(Signature preview)$" },                  float = true})
hl.window_rule({match = {title = "^(Signature preview)$" },                  size = {900, 600} })
hl.window_rule({match = {title = "^(Open File)(.*)$" },                      center = true})
hl.window_rule({match = {title = "^(Open File)(.*)$" },                      float = true})
hl.window_rule({match = {title = "^(Select a File)(.*)$" },                  center = true})
hl.window_rule({match = {title = "^(Select a File)(.*)$" },                  float = true})
hl.window_rule({match = {title = "^(Choose wallpaper)(.*)$" },               center = true})
hl.window_rule({match = {title = "^(Choose wallpaper)(.*)$" },               float = true})
hl.window_rule({match = {title = "^(Choose wallpaper)(.*)$" },               size = {"(monitor_w*0.60)", "(monitor_h*0.65)"} })
hl.window_rule({match = {title = "^(Open Folder)(.*)$" },                    center = true})
hl.window_rule({match = {title = "^(Open Folder)(.*)$" },                    float = true})
hl.window_rule({match = {title = "^(Save As)(.*)$" },                        center = true})
hl.window_rule({match = {title = "^(Save As)(.*)$" },                        float = true})
hl.window_rule({match = {title = "^(Library)(.*)$" },                        center = true})
hl.window_rule({match = {title = "^(Library)(.*)$" },                        float = true})
hl.window_rule({match = {title = "^(File Upload)(.*)$" },                    center = true})
hl.window_rule({match = {title = "^(File Upload)(.*)$" },                    float = true})
hl.window_rule({match = {title = "^(.*)(wants to save)$" },                  center = true})
hl.window_rule({match = {title = "^(.*)(wants to save)$" },                  float = true})
hl.window_rule({match = {title = "^(.*)(wants to open)$" },                  center = true})
hl.window_rule({match = {title = "^(.*)(wants to open)$" },                  float = true})
-- Chromium's profile error box ("Something went wrong when opening your
-- profile") is a bare toplevel with no app_id, so only the title can match it.
-- Tiled it stretches a two-line message across the whole monitor.
hl.window_rule({match = {title = "^(Profile error occurred)$" },             center = true})
hl.window_rule({match = {title = "^(Profile error occurred)$" },             float = true})
-- Portal file choosers by CLASS: apps pass their own dialog titles (Zed's
-- "Open Folder", localized titles), so the title list above cannot cover them.
hl.window_rule({match = {class = "^(xdg-desktop-portal-gtk)$" },             float = true})
hl.window_rule({match = {class = "^(xdg-desktop-portal-gtk)$" },             center = true})
hl.window_rule({match = {class = "^(xdg-desktop-portal-gtk)$" },             size = {"(monitor_w*0.60)", "(monitor_h*0.65)"} })
-- a qt app reports another class on wayland than on xcb: match both forms
hl.window_rule({match = {class = "^(kdialog|org\\.kde\\.kdialog)$" },        float = true})
hl.window_rule({match = {class = "^(kdialog|org\\.kde\\.kdialog)$" },        center = true})
hl.window_rule({match = {class = "^(blueberry\\.py)$" },                     float = true})
hl.window_rule({match = {class = "^(guifetch)$" },                           float = true}) -- FlafyDev/guifetch
hl.window_rule({match = {class = "^(pavucontrol)$" },                        float = true})
hl.window_rule({match = {class = "^(pavucontrol)$" },                        size = {"(monitor_w*0.45)", "(monitor_h*0.45)"} })
hl.window_rule({match = {class = "^(pavucontrol)$" },                        center = true})
hl.window_rule({match = {class = "^(org.pulseaudio.pavucontrol)$" },         float = true})
hl.window_rule({match = {class = "^(org.pulseaudio.pavucontrol)$" },         size = {"(monitor_w*0.45)", "(monitor_h*0.45)"} })
hl.window_rule({match = {class = "^(org.pulseaudio.pavucontrol)$" },         center = true})
hl.window_rule({match = {class = "^(nm-connection-editor)$" },               float = true})
hl.window_rule({match = {class = "^(nm-connection-editor)$" },               size = {"(monitor_w*0.45)", "(monitor_h*0.45)"} })
hl.window_rule({match = {class = "^(nm-connection-editor)$" },               center = true})
hl.window_rule({match = {title = ".*Welcome" },                              float = true})
hl.window_rule({match = {title = ".*Welcome" },                              center = true})
-- 1402x951 is the cheatsheet card measured on 1920x1200. Content-sized, so it does
-- not scale with the monitor; the min() clamps keep it on a smaller panel.
local overlayW = "(min(1402, monitor_w-64))"
local overlayH = "(min(951, monitor_h-92))"
hl.window_rule({match = {title = "^(KOOMPI Settings)$" },                    float = true})
hl.window_rule({match = {title = "^(KOOMPI Settings)$" },                    size = {overlayW, overlayH} })
hl.window_rule({match = {title = "^(KOOMPI Settings)$" },                    center = true})
hl.window_rule({match = {title = ".*Shell conflicts.*" },                    float = true})
hl.window_rule({match = {class = "^(Zotero)$" },                             float = true})
hl.window_rule({match = {class = "^(Zotero)$" },                             size = {"(monitor_w*0.45)", "(monitor_h*0.45)"} })
-- koompi-launch-tui windows (class TUI.<app-id>): floated like the portal chooser
hl.window_rule({match = {class = "^TUI\\." },                                 float = true})
hl.window_rule({match = {class = "^TUI\\." },                                 center = true})
hl.window_rule({match = {class = "^TUI\\." },                                 size = {"(monitor_w*0.60)", "(monitor_h*0.65)"} })
-- later rules win, so the widgets come after the TUI one
-- app widgets (toggle_app_scratchpad.sh): one special workspace each, all floating, centred, 70% x 70%.
-- Telegram (SUPER + T) is a side panel, not a centred widget: rules_telegram.lua.
local widgets = {
    { special = "discord",  match = { class = "^(discord)$" } },
    { special = "whatsapp", match = { class = ".*web\\.whatsapp\\.com.*" } },
    { special = "term",     match = { class = "^(term-scratch)$" } },
    { special = "sysmon",   match = { class = "^(TUI\\.sysmon-scratch)$" } },
}
for _, w in ipairs(widgets) do
    hl.window_rule({match = w.match, workspace = "special:" .. w.special .. " silent"})
    hl.window_rule({match = w.match, float = true})
    hl.window_rule({match = w.match, size = {"(monitor_w*0.7)", "(monitor_h*0.7)"} })
    hl.window_rule({match = w.match, center = true})
end

-- Normal browser classes only, never the chrome --app widget class, so the
-- WhatsApp/Telegram/Discord widgets stay on their special workspaces.
hl.window_rule({match = {class = "^(google-chrome|google-chrome-stable|chromium|brave-browser|firefox|zen|zen-browser|microsoft-edge|opera|librewolf)$" }, workspace = "9"})


-- Move
-- stupid dolphin copy
hl.window_rule({match = {title = "^(Copying — Dolphin)$" }, move = {40, 80}})

-- Tiling
hl.window_rule({match = {class = "^dev\\.warp\\.Warp$" }, tile = true})

-- Picture-in-Picture
hl.window_rule({match = {title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" }, float = true})
hl.window_rule({match = {title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" }, keep_aspect_ratio = true})
hl.window_rule({match = {title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" }, move = {"(monitor_w*0.73)", "(monitor_h*0.72)"} })
hl.window_rule({match = {title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" }, size = {"(monitor_w*0.25)", "(monitor_h*0.25)"} })
hl.window_rule({match = {title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" }, pin = true})

-- Screen sharing
hl.window_rule({match = {title = ".*is sharing (a window|your screen).*" }, float = true})
hl.window_rule({match = {title = ".*is sharing (a window|your screen).*" }, pin = true})
hl.window_rule({match = {title = ".*is sharing (a window|your screen).*" }, move = {"(monitor_w*.5-window_w*.5)", "(monitor_h-window_h-12)"} })

-- --- Tearing ---
hl.window_rule({match = {title = ".*\\.exe" }, immediate = true})
hl.window_rule({match = {title = ".*minecraft.*" }, immediate = true})
hl.window_rule({match = {class = "^(steam_app).*" }, immediate = true})

-- No shadow for tiled windows
hl.window_rule({match = {float = 0 }, no_shadow = true})

-- ######## Workspace rules ########
hl.workspace_rule({ workspace = "special:special", gaps_out = 30 })
hl.workspace_rule({ workspace = "special:telegram", gaps_out = 30 })
hl.workspace_rule({ workspace = "special:discord", gaps_out = 30 })
hl.workspace_rule({ workspace = "special:whatsapp", gaps_out = 30 })
hl.workspace_rule({ workspace = "special:term", gaps_out = 30 })
hl.workspace_rule({ workspace = "special:sysmon", gaps_out = 30 })
-- No single-window rule: a lone window keeps the gap on every edge and its rounded corners,
-- the same as two (test_window_gaps.sh). Filling the screen read as a different style.

-- ######## Layer rules ########
hl.layer_rule({ match = { namespace = ".*" }, xray = true})
hl.layer_rule({ match = { namespace = "walker" }, no_anim = true})
hl.layer_rule({ match = { namespace = "selection" }, no_anim = true})
hl.layer_rule({ match = { namespace = "overview" }, no_anim = true})
hl.layer_rule({ match = { namespace = "anyrun" }, no_anim = true})
hl.layer_rule({ match = { namespace = "indicator.*" }, no_anim = true})
hl.layer_rule({ match = { namespace = "osk" }, no_anim = true})
hl.layer_rule({ match = { namespace = "hyprpicker" }, no_anim = true})

hl.layer_rule({ match = { namespace = "noanim" }, no_anim = true})
hl.layer_rule({ match = { namespace = "gtk-layer-shell" }, blur = true})
hl.layer_rule({ match = { namespace = "gtk-layer-shell" }, ignore_alpha = 0})
hl.layer_rule({ match = { namespace = "launcher" }, blur = true})
hl.layer_rule({ match = { namespace = "launcher" }, ignore_alpha = 0.5})
hl.layer_rule({ match = { namespace = "notifications" }, blur = true})
hl.layer_rule({ match = { namespace = "notifications" }, ignore_alpha = 0.69})
hl.layer_rule({ match = { namespace = "logout_dialog" }, blur = true}) -- wlogout

-- ags
hl.layer_rule({ match = { namespace = "sideleft.*" }, animation = "slide left"})
hl.layer_rule({ match = { namespace = "sideright.*" }, animation = "slide right"})
hl.layer_rule({ match = { namespace = "session[0-9]*" }, blur = true})
hl.layer_rule({ match = { namespace = "bar[0-9]*" }, blur = true})
hl.layer_rule({ match = { namespace = "bar[0-9]*" }, ignore_alpha = 0.6})
-- The global menu dropdown is an xdg popup of the bar, not a layer of its own,
-- so without this it is the only bar surface composited over the raw window
-- below and reads far darker than the bar it hangs off.
hl.layer_rule({ match = { namespace = "bar[0-9]*" }, blur_popups = true})
hl.layer_rule({ match = { namespace = "barcorner.*" }, blur = true})
hl.layer_rule({ match = { namespace = "barcorner.*" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "dock[0-9]*" }, blur = true})
hl.layer_rule({ match = { namespace = "dock[0-9]*" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "indicator.*" }, blur = true})
hl.layer_rule({ match = { namespace = "indicator.*" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "overview[0-9]*" }, blur = true})
hl.layer_rule({ match = { namespace = "overview[0-9]*" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "cheatsheet[0-9]*" }, blur = true})
hl.layer_rule({ match = { namespace = "cheatsheet[0-9]*" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "sideright[0-9]*" }, blur = true})
hl.layer_rule({ match = { namespace = "sideright[0-9]*" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "sideleft[0-9]*" }, blur = true})
hl.layer_rule({ match = { namespace = "sideleft[0-9]*" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "osk[0-9]*" }, blur = true})
hl.layer_rule({ match = { namespace = "osk[0-9]*" }, ignore_alpha = 0.6})

-- Quickshell
-- Quickshell: koompi
hl.layer_rule({ match = { namespace = "quickshell:.*" }, blur_popups = true})
hl.layer_rule({ match = { namespace = "quickshell:.*" }, blur = true})
hl.layer_rule({ match = { namespace = "quickshell:.*" }, ignore_alpha = 0.79})
hl.layer_rule({ match = { namespace = "quickshell:bar" }, animation = "slide"})
-- The bar is glass over the wallpaper: a flat tint from 0.3 alpha (BarContent.glassFloor),
-- under the 0.79 cutoff above, so its own lower cutoff lets the blur through.
hl.layer_rule({ match = { namespace = "quickshell:bar" }, ignore_alpha = 0.2})
-- The bar's menus are cut from that glass (GlobalMenuPopup). They are layers rather than popups
-- because a layer is blurred from the wallpaper, as the bar is, and a popup through the window
-- under it. No layer animation: they scale in themselves, and a fade would cross two menus as
-- the pointer runs along the titles.
hl.layer_rule({ match = { namespace = "quickshell:barMenu" }, ignore_alpha = 0.2})
hl.layer_rule({ match = { namespace = "quickshell:barMenu" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:actionCenter" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:cheatsheet" }, animation = "slide bottom"})
hl.layer_rule({ match = { namespace = "quickshell:dock" }, animation = "slide bottom"})
hl.layer_rule({ match = { namespace = "quickshell:screenCorners" }, animation = "popin 120%"})
hl.layer_rule({ match = { namespace = "quickshell:launchpad" }, no_anim = true})
-- The grid animates itself in; the scrim is what needs blurring behind it, and
-- it sits well under the 0.79 alpha cutoff the quickshell:.* rule applies.
hl.layer_rule({ match = { namespace = "quickshell:launchpad" }, ignore_alpha = 0.05})
hl.layer_rule({ match = { namespace = "quickshell:lockWindowPusher" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:notificationPopup" }, animation = "fade"})
hl.layer_rule({ match = { namespace = "quickshell:onScreenDisplay" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:overlay" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:overlay" }, ignore_alpha = 1})
hl.layer_rule({ match = { namespace = "quickshell:overview" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:osk" }, animation = "slide bottom"})
hl.layer_rule({ match = { namespace = "quickshell:polkit" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:popup" }, xray = false}) -- No weird color for bar tooltips (this in theory should suffice)
hl.layer_rule({ match = { namespace = "quickshell:popup" }, ignore_alpha = 1}) -- No weird color for bar tooltips (but somehow this is necessary)
hl.layer_rule({ match = { namespace = "quickshell:mediaControls" }, ignore_alpha = 1}) -- Same as above
hl.layer_rule({ match = { namespace = "quickshell:reloadPopup" }, animation = "slide"})
-- No layer animation: animating the full-screen layer out leaves its dim scrim on
-- screen after the preview is gone.
hl.layer_rule({ match = { namespace = "quickshell:quicklook" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:regionSelector" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:screenshot" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:session" }, blur = true})
hl.layer_rule({ match = { namespace = "quickshell:session" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:session" }, ignore_alpha = 0})
hl.layer_rule({ match = { namespace = "quickshell:sidebarRight" }, no_anim = true}) -- the shell slides it out from under the bar
hl.layer_rule({ match = { namespace = "quickshell:sidebarLeft" }, animation = "slide left"})
hl.layer_rule({ match = { namespace = "quickshell:verticalBar" }, animation = "slide"})
hl.layer_rule({ match = { namespace = "quickshell:osk" }, order = -1})
-- Quickshell: waffles
hl.layer_rule({ match = { namespace = "quickshell:wNotificationCenter" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:wOnScreenDisplay" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:wStartMenu" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:wTaskView" }, ignore_alpha = 0})
hl.layer_rule({ match = { namespace = "quickshell:wTaskView" }, no_anim = true})

-- Launchers need to be FAST
hl.layer_rule({ match = { namespace = "gtk4-layer-shell" }, no_anim = true})

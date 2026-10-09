local home_dir = os.getenv("HOME")

-- Wayland
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- Applications
local xdg_data_dirs_old = os.getenv("XDG_DATA_DIRS") or ""
local flatpak_data_dirs = home_dir .. "/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share"
-- Reloads re-run this file; without the guard the flatpak paths get prepended
-- again every time and the value grows without bound.
if not string.find(xdg_data_dirs_old, "/var/lib/flatpak/exports/share", 1, true) then
    hl.env("XDG_DATA_DIRS", flatpak_data_dirs .. ":" .. xdg_data_dirs_old)
end

-- Global menu: GTK apps export their menubar over DBus instead of drawing it
hl.env("GTK_MODULES", "appmenu-gtk-module")

-- File dialogs: route GTK3/GTK4/Electron native choosers through the portal so
-- every app gets the same floating centered picker (portal class rules in rules.lua)
hl.env("GTK_USE_PORTAL", "1")

-- KDE's crash handler assumes a Plasma session; outside one it can only park
-- a dead "closed unexpectedly" icon in the tray. Let crashes just exit.
hl.env("KDE_DEBUG", "1")

-- Themes
-- qt exports a menubar only on x11; koompi-launch keeps its xcb_menu_apps there
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
-- qt6ct, not kde: Qt apps read the matugen-rendered qt6ct palette instead of
-- loading plasma-integration (M5/M7 Qt unwind).
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")

-- Cursor: naming a theme that is not on disk falls back unpredictably, so Adwaita stands in until Bibata lands
local cursor_theme = "Bibata-Modern-Classic"
local function theme_installed(name)
    local dirs = { home_dir .. "/.local/share/icons", home_dir .. "/.icons" }
    for dir in (os.getenv("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"):gmatch("[^:]+") do
        dirs[#dirs + 1] = dir .. "/icons"
    end
    for _, dir in ipairs(dirs) do
        local f = io.open(dir .. "/" .. name .. "/index.theme")
        if f then f:close() return true end
    end
    return false
end
if not theme_installed(cursor_theme) then cursor_theme = "Adwaita" end
hl.env("XCURSOR_THEME", cursor_theme)
hl.env("XCURSOR_SIZE", "24")

-- Virtual environment
hl.env("ILLOGICAL_IMPULSE_VIRTUAL_ENV", home_dir .. "/.local/state/quickshell/.venv")

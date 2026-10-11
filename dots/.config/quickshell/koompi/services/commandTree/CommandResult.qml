import qs.modules.common.models

/**
 * A Search row that came out of the command tree. It is a LauncherSearchResult,
 * so SearchItem and the panel's keyboard handling treat it exactly like an app
 * or a window row; the two extra fields are the only thing a leaf draws that
 * the other providers do not.
 *
 *   group      the trailing "· Toggles" label on a flat result
 *   stateText  the right-hand state column ("off", "16 px", "3")
 *   shortcut   the keycaps of the leaf's Hyprland bind, [] when it has none
 */
LauncherSearchResult {
    property string group: ""
    property string stateText: ""
    property var shortcut: []
}

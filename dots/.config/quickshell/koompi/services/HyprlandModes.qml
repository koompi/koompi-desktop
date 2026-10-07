pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * The one owner of the Hyprland options a mode forces. A mode is a flag below, and
 * `holds` names the options it wants: an option is held while any mode that wants
 * it is on, and goes back to the user's own config the moment none does, so one
 * mode turning off never undoes another. Nothing else writes these options.
 */
Singleton {
    id: root

    property bool gameMode: false

    readonly property var flags: ({
        "gameMode": root.gameMode,
        "reduceMotion": Config.options.appearance.reduceMotion,
    })

    readonly property var holds: ({
        "animations:enabled": { "value": 0, "by": ["gameMode", "reduceMotion"] },
        "decoration:blur:enabled": { "value": 0, "by": ["gameMode"] },
        "decoration:shadow:enabled": { "value": 0, "by": ["gameMode"] },
        "decoration:rounding": { "value": 0, "by": ["gameMode"] },
        "general:gaps_in": { "value": 0, "by": ["gameMode"] },
        "general:gaps_out": { "value": 0, "by": ["gameMode"] },
        "general:border_size": { "value": 1, "by": ["gameMode"] },
        "general:allow_tearing": { "value": 1, "by": ["gameMode"] },
    })

    // which held options the overrides file carries right now, read once and then kept
    property var applied: ({})
    property bool fileRead: false
    readonly property bool ready: root.fileRead && Config.ready

    function load() {}

    // what scripts/hyprland/hyprconfigurator.py writes for a key
    function line(key, value) {
        const parts = key.split(":");
        return "hl.config({" + parts.join("={") + "=" + value + "}".repeat(parts.length - 1) + "})";
    }

    // game mode lives in the file only: on when every option only it holds is there
    function adopt(text) {
        const present = {};
        for (const key in root.holds)
            present[key] = text.includes(root.line(key, root.holds[key].value));
        const own = Object.keys(root.holds).filter(key => root.holds[key].by.length === 1 && root.holds[key].by[0] === "gameMode");
        root.applied = present;
        root.gameMode = own.length > 0 && own.every(key => present[key]);
        root.fileRead = true;
    }

    function sync() {
        if (!root.ready)
            return;
        const sets = {};
        const resets = [];
        for (const key in root.holds) {
            const held = root.holds[key].by.some(flag => root.flags[flag]);
            if (held && !root.applied[key])
                sets[key] = root.holds[key].value;
            else if (!held && root.applied[key])
                resets.push(key);
            root.applied[key] = held;
        }
        if (resets.length > 0 || Object.keys(sets).length > 0)
            HyprlandConfig.apply(sets, resets);
    }

    onFlagsChanged: Qt.callLater(root.sync)
    onReadyChanged: Qt.callLater(root.sync)

    FileView {
        path: HyprlandConfig.shellOverridesPath
        onLoaded: root.adopt(text())
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound)
                console.warn(`[HyprlandModes] cannot read ${path}: ${error}`);
            root.adopt("");
        }
    }
}

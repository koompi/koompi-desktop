pragma Singleton

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Wayland

Singleton {
    id: root

    // heuristicLookup is a call: reading this reruns the model once the entries load
    readonly property bool entriesLoaded: DesktopEntries.applications.values.length > 0

    // one app, a class per platform (dolphin, org.kde.dolphin): the entry names it; no-entry kde classes differ by the org.kde. prefix
    function appKey(appClass) {
        const entry = root.entriesLoaded && appClass ? DesktopEntries.heuristicLookup(appClass) : null;
        return (entry?.id ?? appClass ?? "").toLowerCase().replace(/^org\.kde\./, "");
    }

    function isPinned(appId) {
        const key = root.appKey(appId);
        return Config.options.dock.pinnedApps.some(id => root.appKey(id) === key);
    }

    function togglePin(appId) {
        const key = root.appKey(appId);
        if (root.isPinned(appId)) {
            Config.options.dock.pinnedApps = Config.options.dock.pinnedApps.filter(id => root.appKey(id) !== key)
        } else {
            Config.options.dock.pinnedApps = Config.options.dock.pinnedApps.concat([appId])
        }
    }

    function entries(pinnedApps, toplevels, ignoredAppRegexes) {
        var map = new Map();

        for (const appId of pinnedApps) {
            const key = root.appKey(appId);
            if (!map.has(key)) map.set(key, ({
                appId: appId.toLowerCase(),
                pinned: true,
                toplevels: []
            }));
        }

        if (pinnedApps.length > 0) {
            map.set("SEPARATOR", { appId: "SEPARATOR", pinned: false, toplevels: [] });
        }

        const ignoredRegexes = ignoredAppRegexes.map(pattern => new RegExp(pattern, "i"));
        for (const toplevel of toplevels) {
            if (ignoredRegexes.some(re => re.test(toplevel.appId))) continue;
            const key = root.appKey(toplevel.appId);
            if (!map.has(key)) map.set(key, ({
                appId: toplevel.appId.toLowerCase(),
                pinned: false,
                toplevels: []
            }));
            map.get(key).toplevels.push(toplevel);
        }

        return Array.from(map.values(), value => appEntryComp.createObject(null, value));
    }

    property list<var> apps: root.entries(Config.options?.dock.pinnedApps ?? [], ToplevelManager.toplevels.values, Config.options?.dock.ignoredAppRegexes ?? [])

    component TaskbarAppEntry: QtObject {
        id: wrapper
        required property string appId
        required property list<var> toplevels
        required property bool pinned
    }
    Component {
        id: appEntryComp
        TaskbarAppEntry {}
    }
}

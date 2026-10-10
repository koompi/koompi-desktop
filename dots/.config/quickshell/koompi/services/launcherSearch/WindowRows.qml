import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.functions
import QtQuick
import Quickshell.Hyprland

QtObject {
    id: root

    readonly property Component rowComp: Component {
        LauncherSearchResult {}
    }

    readonly property var prepared: HyprlandData.windowList.map(window => ({
        name: Fuzzy.prepare(`${window.title} ${window.class}`),
        entry: window
    }))

    // Window titles run long enough that subsequence matching finds a query in
    // almost any of them, so this scope needs a floor the app list does not.
    readonly property real scoreThreshold: 0.5

    function rows(search: string): var {
        const matches = search.trim() === "" ? HyprlandData.windowList : Fuzzy.go(search, root.prepared, {
            all: true,
            key: "name",
            threshold: root.scoreThreshold
        }).map(r => r.obj.entry);
        return matches.map(window => root.rowComp.createObject(null, {
            key: `window|${window.address}`,
            name: window.title,
            type: Translation.tr("Window"),
            verb: Translation.tr("Switch"),
            iconName: AppSearch.guessIcon(window.class),
            iconType: LauncherSearchResult.IconType.System,
            scopePrefix: Config.options.search.prefix.window,
            execute: () => {
                Hyprland.dispatch(`hl.dsp.focus({ window = "address:${window.address}" })`);
            }
        }));
    }
}
